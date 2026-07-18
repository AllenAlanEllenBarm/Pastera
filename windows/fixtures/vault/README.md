# Vault Compatibility Fixtures

The portable artifact is the KDBX file. Windows Hello, DPAPI, macOS
LocalAuthentication, and Keychain metadata are local convenience layers and
must never be synchronized.

KDBX binary fixtures are generated during tests with synthetic credentials so a
reusable password is not stored in the repository. The Windows test suite must
read a macOS-generated file, update it, and return it to the macOS compatibility
test. Both sides must preserve folder/entry order, tombstones, history, conflict
copies, and the master-password fallback.
