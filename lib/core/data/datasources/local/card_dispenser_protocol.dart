/// Card dispenser serial protocol options.
///
/// ONEPLUS Card Dispenser RS-232 spec:
/// - DIP SW3 OFF: TX uppercase, RX lowercase (legacy)
/// - DIP SW3 ON : TX lowercase, RX lowercase (new; except some commands)
enum CardDispenserProtocol {
  txUpperRxLower,
  txLowerRxLower,
}

