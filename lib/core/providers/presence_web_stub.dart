/// Stub implementation of web presence listeners for non-web platforms.
void registerWebPresenceListeners({
  required void Function() onBeforeUnload,
  required void Function() onVisible,
  required void Function() onHidden,
}) {
  // No-op on mobile/desktop
}
