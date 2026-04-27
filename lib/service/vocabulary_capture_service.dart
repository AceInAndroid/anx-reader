import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/vocabulary.dart';
import 'package:anx_reader/models/vocabulary_item.dart';
import 'package:anx_reader/service/dictionary/english_dictionary.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:uuid/uuid.dart';

typedef VocabularyTranslationLookup = Future<String> Function(
  String text, {
  String? contextText,
});

class VocabularyCaptureResult {
  const VocabularyCaptureResult({
    required this.item,
    required this.created,
    required this.updated,
  });

  final VocabularyItem item;
  final bool created;
  final bool updated;
}

class VocabularyCaptureService {
  VocabularyCaptureService._();

  static Future<VocabularyCaptureResult> capture({
    required String word,
    required String bookId,
    String? bookTitle,
    String? chapterId,
    String? chapterTitle,
    String? contextText,
    String? position,
    VocabularyTranslationLookup? translateLookup,
    Future<EnglishDictionaryEntry?> Function(String word)? dictionaryLookup,
    String? translateToCode,
    DateTime? now,
  }) async {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) {
      throw ArgumentError('word must not be empty');
    }

    final currentTime = now ?? DateTime.now();
    final effectiveContextText = _normalizeOptionalText(contextText);
    final sourceSentence = extractSourceSentence(
      trimmedWord,
      effectiveContextText,
    );
    final contextWindow = extractContextWindow(
      trimmedWord,
      effectiveContextText,
      sourceSentence,
    );
    final translator = translateLookup ?? translateTextOnly;
    final lookupDictionary =
        dictionaryLookup ?? EnglishDictionaryService.lookup;
    final existing = await vocabularyDao.selectByWord(trimmedWord);

    final dictionaryEntryFuture = lookupDictionary(trimmedWord);
    final wordDefinition = await _safeTranslate(
      translator,
      trimmedWord,
      contextText: effectiveContextText,
    );

    String? sourceSentenceTranslation;
    if (sourceSentence.isNotEmpty && sourceSentence != trimmedWord) {
      sourceSentenceTranslation = await _safeTranslate(
        translator,
        sourceSentence,
        contextText: effectiveContextText,
      );
    }

    final dictionaryEntry = await dictionaryEntryFuture;
    final item = _composeItem(
      existing: existing,
      word: trimmedWord,
      bookId: bookId,
      bookTitle: bookTitle,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      sourceSentence: sourceSentence,
      sourceSentenceTranslation: sourceSentenceTranslation,
      contextualDefinition: wordDefinition,
      contextBefore: contextWindow.before,
      contextAfter: contextWindow.after,
      position: position,
      dictionaryEntry: dictionaryEntry,
      translateToCode: translateToCode ?? Prefs().translateTo.code,
      now: currentTime,
    );

    if (existing == null) {
      await vocabularyDao.save(item);
      return VocabularyCaptureResult(
        item: item,
        created: true,
        updated: false,
      );
    }

    if (_hasDiff(existing, item)) {
      await vocabularyDao.updateItem(item);
      return VocabularyCaptureResult(
        item: item,
        created: false,
        updated: true,
      );
    }

    return VocabularyCaptureResult(
      item: existing,
      created: false,
      updated: false,
    );
  }

  static String extractSourceSentence(String word, String? contextText) {
    final text = _normalizeOptionalText(contextText);
    if (text == null) {
      return word;
    }

    final lowerText = text.toLowerCase();
    final index = lowerText.indexOf(word.toLowerCase());
    if (index == -1) {
      return text;
    }

    final sentenceStart = text.lastIndexOf(RegExp(r'[.!?。！？\n]'), index);
    final sentenceEnd = text.indexOf(RegExp(r'[.!?。！？\n]'), index);
    final start = sentenceStart == -1 ? 0 : sentenceStart + 1;
    final end = sentenceEnd == -1 ? text.length : sentenceEnd + 1;
    return text.substring(start, end).trim();
  }

  static VocabularyContextWindow extractContextWindow(
    String word,
    String? contextText,
    String sourceSentence,
  ) {
    final text = _normalizeOptionalText(contextText);
    if (text == null || text == sourceSentence) {
      return const VocabularyContextWindow(before: null, after: null);
    }

    final lowerText = text.toLowerCase();
    final lowerSentence = sourceSentence.toLowerCase();
    final sentenceIndex = lowerText.indexOf(lowerSentence);
    if (sentenceIndex != -1) {
      final before = text.substring(0, sentenceIndex).trim();
      final after =
          text.substring(sentenceIndex + sourceSentence.length).trim();
      return VocabularyContextWindow(
        before: before.isEmpty ? null : before,
        after: after.isEmpty ? null : after,
      );
    }

    final wordIndex = lowerText.indexOf(word.toLowerCase());
    if (wordIndex == -1) {
      return const VocabularyContextWindow(before: null, after: null);
    }

    final before = text.substring(0, wordIndex).trim();
    final after = text.substring(wordIndex + word.length).trim();
    return VocabularyContextWindow(
      before: before.isEmpty ? null : before,
      after: after.isEmpty ? null : after,
    );
  }

  static VocabularyItem _composeItem({
    required VocabularyItem? existing,
    required String word,
    required String bookId,
    required String? bookTitle,
    required String? chapterId,
    required String? chapterTitle,
    required String sourceSentence,
    required String? sourceSentenceTranslation,
    required String? contextualDefinition,
    required String? contextBefore,
    required String? contextAfter,
    required String? position,
    required EnglishDictionaryEntry? dictionaryEntry,
    required String translateToCode,
    required DateTime now,
  }) {
    final translatedDefinition = _normalizeOptionalText(contextualDefinition);
    final englishDefinition = _pickEnglishDefinition(
      dictionaryEntry: dictionaryEntry,
      translatedDefinition: translatedDefinition,
      translateToCode: translateToCode,
      existingValue: existing?.definitionEn,
    );
    final chineseDefinition = _pickChineseDefinition(
      translatedDefinition: translatedDefinition,
      translateToCode: translateToCode,
      existingValue: existing?.definitionCn,
    );
    final sourceTranslation = _normalizeOptionalText(sourceSentenceTranslation);
    final useDictionaryExample =
        sourceSentence == word && _isPresent(dictionaryEntry?.exampleSentence);
    final exampleSentence = useDictionaryExample
        ? dictionaryEntry!.exampleSentence
        : sourceSentence;
    final exampleTranslation = useDictionaryExample
        ? existing?.exampleTranslation
        : _preferNonEmpty(sourceTranslation, existing?.exampleTranslation);

    return VocabularyItem(
      id: existing?.id ?? const Uuid().v4(),
      word: existing?.word ?? word,
      lemma: _preferNonEmpty(
        dictionaryEntry?.lemma,
        _nullableNormalizedWord(word),
        existing?.lemma,
      ),
      phonetic: _preferNonEmpty(
        dictionaryEntry?.phonetic,
        existing?.phonetic,
      ),
      definitionCn: chineseDefinition,
      definitionEn: englishDefinition,
      partOfSpeech: _preferNonEmpty(
        dictionaryEntry?.partOfSpeech,
        existing?.partOfSpeech,
      ),
      audioUrl: _preferNonEmpty(
        dictionaryEntry?.audioUrl,
        existing?.audioUrl,
      ),
      bookId: existing?.bookId.isNotEmpty == true ? existing!.bookId : bookId,
      bookTitle: _preferNonEmpty(bookTitle, existing?.bookTitle),
      chapterId: _preferNonEmpty(chapterId, existing?.chapterId),
      chapterTitle: _preferNonEmpty(chapterTitle, existing?.chapterTitle),
      sourceSentence:
          _preferNonEmpty(sourceSentence, existing?.sourceSentence) ?? word,
      sourceSentenceTranslation: _preferNonEmpty(
        sourceTranslation,
        existing?.sourceSentenceTranslation,
      ),
      contextualDefinition: _preferNonEmpty(
        translatedDefinition,
        englishDefinition,
        chineseDefinition,
        existing?.contextualDefinition,
      ),
      contextBefore: _preferNonEmpty(contextBefore, existing?.contextBefore),
      contextAfter: _preferNonEmpty(contextAfter, existing?.contextAfter),
      exampleSentence: _preferNonEmpty(
        exampleSentence,
        existing?.exampleSentence,
      ),
      exampleTranslation: exampleTranslation,
      position: _preferNonEmpty(position, existing?.position),
      reviewStage: existing?.reviewStage ?? 0,
      nextReviewAt: existing?.nextReviewAt ?? now,
      lastReviewedAt: existing?.lastReviewedAt,
      familiarity: existing?.familiarity ?? VocabularyFamiliarity.newWord,
      correctCount: existing?.correctCount ?? 0,
      wrongCount: existing?.wrongCount ?? 0,
      isMastered: existing?.isMastered ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  static String? _pickEnglishDefinition({
    required EnglishDictionaryEntry? dictionaryEntry,
    required String? translatedDefinition,
    required String translateToCode,
    required String? existingValue,
  }) {
    if (_isPresent(dictionaryEntry?.definitionEn)) {
      return dictionaryEntry!.definitionEn;
    }
    if (!translateToCode.startsWith('zh') && _isPresent(translatedDefinition)) {
      return translatedDefinition;
    }
    return existingValue;
  }

  static String? _pickChineseDefinition({
    required String? translatedDefinition,
    required String translateToCode,
    required String? existingValue,
  }) {
    if (translateToCode.startsWith('zh') && _isPresent(translatedDefinition)) {
      return translatedDefinition;
    }
    return existingValue;
  }

  static Future<String?> _safeTranslate(
    VocabularyTranslationLookup translator,
    String text, {
    String? contextText,
  }) async {
    try {
      return _normalizeOptionalText(
        await translator(text, contextText: contextText),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _hasDiff(VocabularyItem left, VocabularyItem right) {
    return left.copyWith(updatedAt: right.updatedAt).toJson().toString() !=
        right.toJson().toString();
  }

  static String? _nullableNormalizedWord(String word) {
    final normalized = VocabularyItem.normalizeWord(word);
    if (normalized.isEmpty) return null;
    return normalized;
  }

  static String? _normalizeOptionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static bool _isPresent(String? value) {
    return value?.trim().isNotEmpty ?? false;
  }

  static String? _preferNonEmpty(
    String? first, [
    String? second,
    String? third,
    String? fourth,
  ]) {
    for (final value in [first, second, third, fourth]) {
      final normalized = _normalizeOptionalText(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }
}

class VocabularyContextWindow {
  const VocabularyContextWindow({
    required this.before,
    required this.after,
  });

  final String? before;
  final String? after;
}
