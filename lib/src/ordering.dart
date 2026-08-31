List<T> moveItem<T>(List<T> items, int oldIndex, int newIndex) {
  final reordered = List<T>.of(items);
  final item = reordered.removeAt(oldIndex);
  reordered.insert(newIndex, item);
  return reordered;
}
