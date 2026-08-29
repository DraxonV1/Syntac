class ProviderErrorDetails {
  ProviderErrorDetails({
    required this.providerName,
    required this.modelId,
    required this.requestUrl,
    required this.errorType,
    DateTime? timestamp,
    this.method,
    this.httpStatus,
    this.responseBody,
    this.exceptionMessage,
    this.headers,
    this.streamStarted = false,
    this.chunksReceived = 0,
    this.finalResponse,
  }) : timestamp = timestamp ?? DateTime.now();

  final String providerName;
  final String modelId;
  final String requestUrl;
  final String errorType;
  final DateTime timestamp;
  final String? method;
  final int? httpStatus;
  final String? responseBody;
  final String? exceptionMessage;
  final Map<String, String>? headers;
  final bool streamStarted;
  final int chunksReceived;
  final String? finalResponse;

  ProviderErrorDetails copyWith({
    String? providerName,
    String? modelId,
    String? requestUrl,
    String? errorType,
    DateTime? timestamp,
    String? method,
    int? httpStatus,
    String? responseBody,
    String? exceptionMessage,
    Map<String, String>? headers,
    bool? streamStarted,
    int? chunksReceived,
    String? finalResponse,
  }) => ProviderErrorDetails(
    providerName: providerName ?? this.providerName,
    modelId: modelId ?? this.modelId,
    requestUrl: requestUrl ?? this.requestUrl,
    errorType: errorType ?? this.errorType,
    timestamp: timestamp ?? this.timestamp,
    method: method ?? this.method,
    httpStatus: httpStatus ?? this.httpStatus,
    responseBody: responseBody ?? this.responseBody,
    exceptionMessage: exceptionMessage ?? this.exceptionMessage,
    headers: headers ?? this.headers,
    streamStarted: streamStarted ?? this.streamStarted,
    chunksReceived: chunksReceived ?? this.chunksReceived,
    finalResponse: finalResponse ?? this.finalResponse,
  );

  Map<String, Object?> toJson() => {
    'provider': providerName,
    'model': modelId,
    'requestUrl': _redactUrl(requestUrl),
    if (method != null) 'method': method,
    if (httpStatus != null) 'httpStatus': httpStatus,
    'errorType': errorType,
    if (headers != null)
      'headers': headers!.map(
        (key, value) => MapEntry(
          key,
          _isSecretHeader(key) ? '[redacted]' : redactSecrets(value),
        ),
      ),
    if (responseBody != null) 'responseBody': redactSecrets(responseBody!),
    if (exceptionMessage != null)
      'exceptionMessage': redactSecrets(exceptionMessage!),
    'streamStarted': streamStarted,
    'chunksReceived': chunksReceived,
    if (finalResponse != null) 'finalResponse': redactSecrets(finalResponse!),
    'timestamp': timestamp.toIso8601String(),
  };

  String toDisplayText({String title = 'Request failed'}) {
    final lines = <String>[
      title,
      'Provider: $providerName',
      if (modelId.isNotEmpty) 'Model: $modelId',
      if (httpStatus != null) 'Status: $httpStatus',
      if (method != null) 'Method: $method',
      if (requestUrl.isNotEmpty) 'Endpoint: ${_redactUrl(requestUrl)}',
      'Error type: $errorType',
      'Stream started: $streamStarted',
      'Chunks received: $chunksReceived',
    ];
    final safeException = exceptionMessage == null
        ? null
        : redactSecrets(exceptionMessage!);
    if (safeException != null && safeException.isNotEmpty) {
      lines.add('Message: $safeException');
    }
    final safeBody = responseBody == null ? null : redactSecrets(responseBody!);
    if (safeBody != null && safeBody.isNotEmpty) {
      lines.add('Response:');
      lines.add(_limit(safeBody, 4000));
    }
    final safeFinal = finalResponse == null
        ? null
        : redactSecrets(finalResponse!);
    if (safeFinal != null && safeFinal.isNotEmpty) {
      lines.add('Final response:');
      lines.add(_limit(safeFinal, 2000));
    }
    return lines.join('\n');
  }
}

String redactSecrets(String input) {
  var output = input;
  output = output.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
    'Bearer [redacted]',
  );
  output = output.replaceAll(
    RegExp(
      r'''((?:"|')?(?:access_token|refresh_token|api_key|apikey|x-api-key|key|token|Authorization|authorization)(?:"|')?\s*[:=]\s*(?:"|')?)[^"'&\s,}]+''',
      caseSensitive: false,
    ),
    r'$1[redacted]',
  );
  output = output.replaceAll(
    RegExp(
      r'(access_token|refresh_token|api_key|apikey|x-api-key|key|token)=([^&\s]+)',
      caseSensitive: false,
    ),
    r'$1=[redacted]',
  );
  return output;
}

String _redactUrl(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasQuery) return redactSecrets(input);
  final safeParams = uri.queryParameters.map(
    (key, value) =>
        MapEntry(key, _isSecretQueryKey(key) ? '[redacted]' : value),
  );
  return uri.replace(queryParameters: safeParams).toString();
}

bool _isSecretHeader(String key) {
  final lower = key.toLowerCase();
  return lower == 'authorization' ||
      lower == 'x-api-key' ||
      lower.contains('token') ||
      lower.contains('secret') ||
      lower.contains('key');
}

bool _isSecretQueryKey(String key) {
  final lower = key.toLowerCase();
  return lower.contains('token') ||
      lower.contains('secret') ||
      lower.contains('key') ||
      lower == 'code';
}

String _limit(String input, int max) =>
    input.length <= max ? input : '${input.substring(0, max)}…';
