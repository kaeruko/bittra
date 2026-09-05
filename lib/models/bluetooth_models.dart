enum RequestStatus { requested, received, failed, timeout }

class Encounter {
  final String id;
  final String peerId;
  final String teaser;
  final DateTime receivedAt;
  final String dedupeKey;
  final DateTime lastSeenAt;
  final int count;
  final int rssi;

  const Encounter({
    required this.id,
    required this.peerId,
    required this.teaser,
    required this.receivedAt,
    required this.dedupeKey,
    required this.lastSeenAt,
    this.count = 1,
    this.rssi = 0,
  });

  Encounter copyWith({
    String? id,
    String? peerId,
    String? teaser,
    DateTime? receivedAt,
    String? dedupeKey,
    DateTime? lastSeenAt,
    int? count,
    int? rssi,
  }) {
    return Encounter(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      teaser: teaser ?? this.teaser,
      receivedAt: receivedAt ?? this.receivedAt,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      count: count ?? this.count,
      rssi: rssi ?? this.rssi,
    );
  }
}

class RequestLog {
  final String id;
  final String encounterId;
  final String? teaser;
  final RequestStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? body;
  final String? error;

  const RequestLog({
    required this.id,
    required this.encounterId,
    this.teaser,
    required this.status,
    required this.requestedAt,
    this.resolvedAt,
    this.body,
    this.error,
  });

  RequestLog copyWith({
    String? id,
    String? encounterId,
    String? teaser,
    RequestStatus? status,
    DateTime? requestedAt,
    DateTime? resolvedAt,
    String? body,
    String? error,
  }) {
    return RequestLog(
      id: id ?? this.id,
      encounterId: encounterId ?? this.encounterId,
      teaser: teaser ?? this.teaser,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      body: body ?? this.body,
      error: error ?? this.error,
    );
  }
}

class SentNotice {
  final String id;
  final String teaser;
  final String body;
  final DateTime sentAt;
  final int receivedCount;

  const SentNotice({
    required this.id,
    required this.teaser,
    required this.body,
    required this.sentAt,
    this.receivedCount = 0,
  });

  SentNotice copyWith({
    String? id,
    String? teaser,
    String? body,
    DateTime? sentAt,
    int? receivedCount,
  }) {
    return SentNotice(
      id: id ?? this.id,
      teaser: teaser ?? this.teaser,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      receivedCount: receivedCount ?? this.receivedCount,
    );
  }
}
