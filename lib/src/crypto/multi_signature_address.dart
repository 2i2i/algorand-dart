import 'dart:convert';
import 'dart:typed_data';

import 'package:algorand_dart/src/crypto/crypto.dart';
import 'package:algorand_dart/src/exceptions/exceptions.dart';
import 'package:algorand_dart/src/models/models.dart';
import 'package:algorand_dart/src/utils/message_packable.dart';
import 'package:buffer/buffer.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// Multisignature accounts are a logical representation of an ordered set of
/// addresses with a threshold and version.
///
/// Multisignature accounts can perform the same operations as other accounts,
/// including sending transactions and participating in consensus.
///
/// The address for a multisignature account is essentially a hash of the
/// ordered list of accounts, the threshold and version values.
/// The threshold determines how many signatures are required to process any
/// transaction from this multisignature account.
///
/// MultisigAddress is a convenience class for handling multisignature public
/// identities.
class MultiSigAddress extends Equatable implements MessagePackable {
  static const MULTISIG_PREFIX = 'MultisigAddr';

  final int version;
  final int threshold;
  final List<Ed25519PublicKey> publicKeys;

  MultiSigAddress({
    required this.version,
    required this.threshold,
    required this.publicKeys,
  }) {
    if (version != 1) {
      throw AlgorandException(message: 'Unknown msig version');
    }
    if (threshold == 0 || publicKeys.isEmpty || threshold > publicKeys.length) {
      throw AlgorandException(message: 'Invalid threshold');
    }
  }

  /// Helper method to convert list of byte[]s to list of Ed25519PublicKeys.
  static List<Ed25519PublicKey> toKeys(List<Uint8List> keys) {
    return keys.map((key) => Ed25519PublicKey(bytes: key)).toList();
  }

  /// Creates a multisig transaction from the input and the multisig account.
  Future<SignedTransaction?> sign({
    required Account account,
    required RawTransaction transaction,
  }) async {
    final sender = transaction.sender;
    if (sender == null) {
      throw AlgorandException(message: 'Sender is not valid');
    }

    // check that from addr of tx matches multisig preimage
    if (sender.encodedAddress != toString()) {
      throw AlgorandException(
        message: 'Transaction sender does not match multisig account',
      );
    }

    // check that account secret key is in multisig pk list
    final publicKey = Ed25519PublicKey(
      bytes: Uint8List.fromList(account.publicKey.bytes),
    );

    final index = publicKeys.indexOf(publicKey);
    if (index == -1) {
      throw AlgorandException(
        message: 'Multisig account does not contain this secret key',
      );
    }

    // Create the multisignature
    final signedTx = await transaction.sign(account);

    final subsigs = <MultisigSubsig>[];
    for (var i = 0; i < publicKeys.length; i++) {
      if (i == index) {
        subsigs.add(
          MultisigSubsig(
            key: publicKey,
            signature: Signature(
              bytes: signedTx.signature ?? Uint8List.fromList([]),
            ),
          ),
        );
      } else {
        subsigs.add(MultisigSubsig(key: publicKeys[i]));
      }
    }

    final mSig = MultiSignature(
      version: version,
      threshold: threshold,
      subsigs: subsigs,
    );

    // TODO Add support for MSA
    return SignedTransaction(transaction: transaction);
  }

  /// Convert the MultiSignature Address to more easily represent as a string.
  Address toAddress() {
    final numPkBytes = Ed25519PublicKey.KEY_LEN_BYTES * publicKeys.length;
    final length = MULTISIG_PREFIX.length + 2 + numPkBytes;
    final writer = ByteDataWriter(bufferLength: length);
    writer.write(utf8.encode(MULTISIG_PREFIX));
    writer.writeUint8(version);
    writer.writeUint8(threshold);
    for (var key in publicKeys) {
      writer.write(key.bytes);
    }

    final digest = sha512256.convert(writer.toBytes());
    return Address(publicKey: Uint8List.fromList(digest.bytes));
  }

  @override
  Map<String, dynamic> toMessagePack() {
    return {
      'version': version,
      'threshold': threshold,
      'publicKeys': publicKeys.map((key) => key.bytes).toList(),
    };
  }

  @override
  String toString() {
    return toAddress().encodedAddress;
  }

  @override
  List<Object?> get props => [version, threshold, ...publicKeys];
}
