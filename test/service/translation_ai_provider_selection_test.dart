import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/translate/ai.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/translation_ai_provider_resolver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TranslationAiProviderResolver', () {
    test('uses dedicated provider when runnable', () {
      final resolution = TranslationAiProviderResolver.resolve(
        providers: [_provider('general'), _provider('translation')],
        selectedProviderId: 'general',
        translationProviderId: 'translation',
      );

      expect(resolution.effectiveProviderId, 'translation');
      expect(resolution.usedDedicatedProvider, isTrue);
      expect(resolution.invalidDedicatedProviderId, isNull);
    });

    test('falls back to general provider when dedicated provider is unset', () {
      final resolution = TranslationAiProviderResolver.resolve(
        providers: [_provider('general'), _provider('translation')],
        selectedProviderId: 'general',
        translationProviderId: null,
      );

      expect(resolution.effectiveProviderId, 'general');
      expect(resolution.usedDedicatedProvider, isFalse);
      expect(resolution.invalidDedicatedProviderId, isNull);
    });

    test('reports invalid dedicated provider and falls back to general', () {
      final resolution = TranslationAiProviderResolver.resolve(
        providers: [
          _provider('general'),
          _provider('translation', enabled: false),
        ],
        selectedProviderId: 'general',
        translationProviderId: 'translation',
      );

      expect(resolution.effectiveProviderId, 'general');
      expect(resolution.usedDedicatedProvider, isFalse);
      expect(resolution.invalidDedicatedProviderId, 'translation');
    });

    test('falls back to first runnable provider when selected is invalid', () {
      final resolution = TranslationAiProviderResolver.resolve(
        providers: [
          _provider('general', enabled: false),
          _provider('first-runnable'),
        ],
        selectedProviderId: 'general',
        translationProviderId: null,
      );

      expect(resolution.effectiveProviderId, 'first-runnable');
      expect(resolution.usedDedicatedProvider, isFalse);
    });
  });

  group('AiTranslateProvider provider routing', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Prefs().prefs = await SharedPreferences.getInstance();
      Prefs().saveAiProviders([
        _provider('general').toJson(),
        _provider('translation').toJson(),
        _provider('fallback').toJson(),
      ]);
      Prefs().selectedAiService = 'general';
      Prefs().translationAiProvider = 'translation';
    });

    test('runtime resolver clears stale dedicated provider ids', () async {
      Prefs().translationAiProvider = 'missing';
      final provider = AiTranslateProvider(
        streamWidgetBuilder: _recordingWidgetBuilder(_IdentifierRecorder()),
      );

      expect(provider.resolvePrimaryTranslationProviderIdForTest(), 'general');
      expect(Prefs().translationAiProvider, isNull);
    });

    test('translate passes dedicated provider id to AiStream boundary', () {
      final recorder = _IdentifierRecorder();
      final provider = AiTranslateProvider(
        streamWidgetBuilder: _recordingWidgetBuilder(recorder),
      );

      provider.translate(
          'hello', LangListEnum.english, LangListEnum.simplifiedChinese);

      expect(recorder.widgetIdentifier, 'translation');
    });

    test(
      'translateStream passes dedicated provider id to stream boundary',
      () async {
        final recorder = _IdentifierRecorder();
        final provider = AiTranslateProvider(
          streamGenerator: (messages, {identifier}) {
            recorder.streamIdentifier = identifier;
            return Stream.value('你好');
          },
        );

        final results = await provider
            .translateStream(
                'hello', LangListEnum.english, LangListEnum.simplifiedChinese)
            .toList();

        expect(results, ['你好']);
        expect(recorder.streamIdentifier, 'translation');
      },
    );

    test(
      'translateTextOnly passes dedicated provider id to text boundary',
      () async {
        final recorder = _IdentifierRecorder();
        final provider = AiTranslateProvider(
          textGenerator: (messages, {identifier}) async {
            recorder.textIdentifier = identifier;
            return '你好';
          },
        );

        final result = await provider.translateTextOnly(
          'hello',
          LangListEnum.english,
          LangListEnum.simplifiedChinese,
        );

        expect(result, '你好');
        expect(recorder.textIdentifier, 'translation');
      },
    );

    test(
      'translateTextOnly excludes dedicated primary when falling back',
      () async {
        Prefs().aiFallbackProvider = 'fallback';
        final identifiers = <String?>[];
        final provider = AiTranslateProvider(
          textGenerator: (messages, {identifier}) async {
            identifiers.add(identifier);
            if (identifier == 'translation') {
              return '''
Source text:
hello

Output only the final translated text.
Do not output the source text.
''';
            }
            return 'fallback translation';
          },
        );

        final result = await provider.translateTextOnly(
          'hello',
          LangListEnum.english,
          LangListEnum.simplifiedChinese,
        );

        expect(result, 'fallback translation');
        expect(identifiers, ['translation', 'fallback']);
      },
    );
  });

  group('translate fallback chain', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Prefs().prefs = await SharedPreferences.getInstance();
    });

    test('adds AI fallback for non-AI primary when AI provider is runnable',
        () {
      Prefs().saveAiProviders([
        _provider('general').toJson(),
        _provider('translation').toJson(),
      ]);
      Prefs().selectedAiService = 'general';
      Prefs().translationAiProvider = 'translation';

      final services = fallbackTranslateServicesForTest(
        TranslateService.microsoftApi,
      );

      expect(services.first, TranslateService.microsoftApi);
      expect(services, contains(TranslateService.ai));
    });

    test('does not add AI fallback when no AI provider is runnable', () {
      Prefs().saveAiProviders([
        _provider('disabled', enabled: false).toJson(),
      ]);
      Prefs().selectedAiService = 'disabled';

      final services = fallbackTranslateServicesForTest(
        TranslateService.microsoftApi,
      );

      expect(services, isNot(contains(TranslateService.ai)));
    });
  });
}

AiProvider _provider(
  String id, {
  bool enabled = true,
  List<AiApiKey>? apiKeys,
}) {
  return AiProvider(
    id: id,
    title: id,
    url: 'http://localhost:1234/v1',
    protocol: AiProtocol.openai,
    enabled: enabled,
    apiKeys: apiKeys ?? [AiApiKey(id: '$id-key', key: '$id-api-key')],
    model: '$id-model',
  );
}

AiTranslationWidgetBuilder _recordingWidgetBuilder(
  _IdentifierRecorder recorder,
) {
  return (prompt, {identifier}) {
    recorder.widgetIdentifier = identifier;
    return const SizedBox.shrink();
  };
}

class _IdentifierRecorder {
  String? widgetIdentifier;
  String? streamIdentifier;
  String? textIdentifier;
}
