enum LongPressSelectionMode {
  word,
  sentence;

  static LongPressSelectionMode fromCode(String? value) {
    return values.firstWhere(
      (item) => item.name == value,
      // Preserve the smallest useful native unit by default: one CJK
      // character or one Latin word. Sentence remains an explicit setting.
      orElse: () => LongPressSelectionMode.word,
    );
  }
}
