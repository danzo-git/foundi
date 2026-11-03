import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/data/firebase_rich_conversation_repository.dart';
import 'package:foundi/features/conversations/domain/rich_conversation_repository.dart';

class Functions extends Fake implements FirebaseFunctions {}

class Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[], bodies = <List<int>>[];
  int status = 200;
  List<int>? binary;
  Map<String, dynamic> reply = {'state': 'ready'};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = stream == null ? <Uint8List>[] : await stream.toList();
    bodies.add(chunks.expand((c) => c).toList());
    return binary != null
        ? ResponseBody.fromBytes(binary!, status)
        : ResponseBody.fromString(
            jsonEncode(reply),
            status,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'Dio transfers exact binary bytes with auth headers, preserves reservation identity and reports quarantine without success',
    () async {
      final transport = Transport(), calls = <Map<String, dynamic>>[];
      var reserved = 'reserved';
      final repo = FirebaseRichConversationRepository(
        Functions(),
        endpointBase: 'https://unit.invalid',
        http: Dio()..httpClientAdapter = transport,
        accessToken: () async => 'unit-token',
        callable: (name, data) async {
          calls.add({'name': name, ...data});
          return {
            'state': name == 'cancelConversationAttachment'
                ? 'cancelled'
                : reserved,
          };
        },
      );
      final bytes = File('functions/test/fixtures/photo.png').readAsBytesSync(),
          draft = AttachmentDraft(
            bytes: bytes,
            originalName: 'photo.png',
            type: 'image',
          );
      transport.status = 202;
      transport.reply = {'state': 'awaiting_scan'};
      final state = await repo.sendAttachment(
        'conversation',
        'stable-message',
        draft,
        cancellation: AttachmentCancellation(),
        onProgress: (_) {},
      );
      expect(state, 'awaiting_scan');
      expect(transport.bodies.single, bytes);
      expect(calls.single['messageId'], 'stable-message');
      expect(calls.single['sha256'], draft.digest);
      expect(
        transport.requests.single.headers['Authorization'],
        'Bearer unit-token',
      );
      expect(
        transport.requests.single.headers['X-Conversation-Id'],
        'conversation',
      );
      expect(transport.requests.single.uri.query, isEmpty);
      reserved = 'ready';
      expect(
        await repo.sendAttachment(
          'conversation',
          'stable-message',
          draft,
          cancellation: AttachmentCancellation(),
          onProgress: (_) {},
        ),
        'ready',
      );
      expect(transport.requests.length, 1);
      reserved = 'reserved';
      final cancel = AttachmentCancellation()..cancel();
      expect(
        await repo.sendAttachment(
          'conversation',
          'cancelled-message',
          draft,
          cancellation: cancel,
          onProgress: (_) {},
        ),
        'cancelled',
      );
      expect(calls.last['name'], 'cancelConversationAttachment');
      expect(transport.requests.length, 1);
      await repo.shareContact(
        'conversation',
        'contact-message',
        '+2250700000000',
      );
      expect(calls.last['consent'], true);
      expect(calls.last['type'], 'contact');
      expect(calls.last.containsKey('senderUid'), false);
    },
  );
  test(
    'private HTTP read returns bytes only after authenticated response; backend denial remains an error',
    () async {
      final transport = Transport(),
          repo = FirebaseRichConversationRepository(
            Functions(),
            endpointBase: 'https://unit.invalid',
            http: Dio()..httpClientAdapter = transport,
            accessToken: () async => 'unit-token',
            callable: (_, _) async => {'state': 'reserved'},
          );
      final bytes = File(
        'functions/test/fixtures/document.pdf',
      ).readAsBytesSync();
      transport.binary = bytes;
      expect(await repo.readAttachment('conversation', 'document'), bytes);
      expect(
        transport.requests.single.headers['Authorization'],
        'Bearer unit-token',
      );
      expect(transport.requests.single.uri.queryParameters, {
        'conversationId': 'conversation',
        'messageId': 'document',
      });
      transport.binary = null;
      transport.status = 403;
      transport.reply = {
        'error': {
          'code': 'permission-denied',
          'message': 'Cette discussion est privée.',
        },
      };
      await expectLater(
        repo.readAttachment('conversation', 'document'),
        throwsA(isA<AuthFailure>()),
      );
      final draft = AttachmentDraft(
        bytes: File('functions/test/fixtures/photo.png').readAsBytesSync(),
        originalName: 'photo.png',
        type: 'image',
      );
      await expectLater(
        repo.sendAttachment(
          'conversation',
          'forbidden',
          draft,
          cancellation: AttachmentCancellation(),
          onProgress: (_) {},
        ),
        throwsA(isA<AuthFailure>()),
      );
    },
  );
}
