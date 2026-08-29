class PlayerSeekCoordinator {
  int _generation = 0;
  int get generation => _generation;
  int next() => ++_generation;
  bool accepts(int generation) => generation == _generation;
}
