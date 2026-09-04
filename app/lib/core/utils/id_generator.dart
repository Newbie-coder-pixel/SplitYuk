/// Generates ids unique within a single in-memory session. Session data is
/// never persisted or shared across devices (PRD §3), so a lightweight
/// counter + timestamp is sufficient — no need for a UUID dependency.
class IdGenerator {
  IdGenerator._();

  static int _counter = 0;

  static String next(String prefix) {
    _counter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}
