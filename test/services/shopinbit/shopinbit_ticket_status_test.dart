import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/services/shopinbit/src/models/ticket.dart';

void main() {
  test('empty tracking values do not create a bogus HTTPS link', () {
    expect(splitTrackingLinks(null), isEmpty);
    expect(splitTrackingLinks(''), isEmpty);
    expect(splitTrackingLinks(' , | ; '), isEmpty);
  });

  test('tracking values keep only valid web links', () {
    expect(
      splitTrackingLinks(
        'tracking.example/one | https://tracking.example/two; javascript:',
      ),
      ['https://tracking.example/one', 'https://tracking.example/two'],
    );
  });

  test('ticket status timestamps are normalized to UTC', () {
    final status = TicketStatus.fromJson({
      'ticket_id': 42,
      'state': 'CHECKING',
      'updated_at': '2026-07-31T12:00:00-05:00',
      'last_agent_message_at': '2026-07-31T12:01:00-05:00',
      'tracking_link': null,
    });

    expect(status.updatedAt, DateTime.utc(2026, 7, 31, 17));
    expect(status.updatedAt.isUtc, isTrue);
    expect(status.lastAgentMessageAt, DateTime.utc(2026, 7, 31, 17, 1));
  });

  test('newer server timestamps refresh ticket details', () {
    final incoming = _status(
      state: TicketState.checking,
      updatedAt: DateTime.utc(2026, 7, 31, 17, 1),
    );

    expect(
      shouldRefreshTicketDetails(
        incoming: incoming,
        storedState: TicketState.checking.value,
        storedUpdatedAt: DateTime.utc(2026, 7, 31, 17),
      ),
      isTrue,
    );
  });

  test('a changed state refreshes details even at the same timestamp', () {
    final timestamp = DateTime.utc(2026, 7, 31, 17);
    final incoming = _status(
      state: TicketState.inProgress,
      updatedAt: timestamp,
    );

    expect(
      shouldRefreshTicketDetails(
        incoming: incoming,
        storedState: TicketState.checking.value,
        storedUpdatedAt: timestamp,
      ),
      isTrue,
    );
  });
}

TicketStatus _status({
  required TicketState state,
  required DateTime updatedAt,
}) => TicketStatus(
  ticketId: 42,
  state: state,
  stateRaw: state.value,
  updatedAt: updatedAt,
);
