import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../core/cancellation.dart';
import 'ai_provider.dart';

void logDetailedAIError(
  Object error,
  StackTrace stackTrace, {
  String context = 'AI provider request failed',
}) {
  assert(() {
    developer.log(
      context,
      name: 'syntac.ai',
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
    return true;
  }());
}

String describeAIErrorForUser(
  Object error, {
  String providerName = 'provider',
}) {
  final name = providerName.trim().isEmpty ? 'provider' : providerName.trim();
  if (error is OperationCancelledException) return 'Stopped by user';
  if (error is AIProviderException) {
    final details = error.details;
    if (details != null &&
        (details.httpStatus != null ||
            (details.responseBody?.isNotEmpty ?? false) ||
            (details.finalResponse?.isNotEmpty ?? false))) {
      return details
          .copyWith(providerName: name)
          .toDisplayText(title: 'Provider response');
    }
    final transportKind = _transportErrorKind(error);
    if (transportKind != null) {
      return _displayProviderError(
        transportKind,
        providerName: name,
        statusCode: error.statusCode,
      );
    }
    if (details != null) {
      return details.copyWith(providerName: name).toDisplayText();
    }
    return _displayProviderError(
      error.kind,
      providerName: name,
      statusCode: error.statusCode,
    );
  }

  if (error is TimeoutException) return 'timeout: Agent operation timed out.';
  if (error is FileSystemException) {
    final path = error.path == null ? '' : ' (${error.path})';
    return 'filesystem_error: ${_safeErrorText(error.message)}$path';
  }
  if (error is FormatException) {
    return 'invalid_agent_data: ${_safeErrorText(error.message)}';
  }
  if (error is ArgumentError) {
    return 'tool_argument_error: ${_safeErrorText(error.message)}';
  }

  final details = _safeErrorText(error.toString());
  if (details.contains('Missing API key')) {
    return 'missing_credentials: Missing API key for $name.';
  }
  if (details.contains('Configure an OpenAI-compatible provider')) {
    return 'missing_provider: Configure an AI provider before running the agent.';
  }
  if (error is StateError) {
    return 'agent_state_error: ${_stripDartPrefix(details, 'Bad state: ')}';
  }
  return 'internal_exception: ${error.runtimeType}: $details';
}

String? _transportErrorKind(AIProviderException error) {
  final raw = [
    error.kind,
    error.message,
    error.details?.exceptionMessage ?? '',
  ].join(' ').toLowerCase();
  if (error.kind == 'dns_failure' ||
      raw.contains('failed host lookup') ||
      raw.contains('no address associated with hostname') ||
      raw.contains('nodename nor servname') ||
      raw.contains('name or service not known')) {
    return 'dns_failure';
  }
  if (error.kind == 'tls_failure' || raw.contains('handshakeexception')) {
    return 'tls_failure';
  }
  if (error.kind == 'timeout' ||
      raw.contains('timeout') ||
      raw.contains('timed out')) {
    return 'timeout';
  }
  if (error.kind == 'no_network' ||
      raw.contains('network is unreachable') ||
      raw.contains('no route to host')) {
    return 'no_network';
  }
  if (error.kind == 'network_error' ||
      raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset')) {
    return 'network_error';
  }
  return null;
}

String _displayProviderError(
  String kind, {
  required String providerName,
  int? statusCode,
}) => switch (kind) {
  'malformed_endpoint' =>
    'Provider URL is invalid. Enter a valid http:// or https:// URL.',
  'no_network' =>
    "Couldn't connect to $providerName. Check your internet connection and try again.",
  'dns_failure' =>
    "Couldn't find $providerName. Check your internet connection and provider URL.",
  'tls_failure' =>
    "Couldn't verify the secure connection to $providerName. Check device date/time and network settings.",
  'timeout' => '$providerName did not respond in time. Try again.',
  'auth_error' => '$providerName rejected the request. Check the API key.',
  'oauth_error' => '$providerName sign-in failed. Try again.',
  'rate_limited' => '$providerName rate limit reached. Try again later.',
  'context_length' =>
    '$providerName rejected the request because context is too large.',
  'bad_request' =>
    '$providerName rejected the request. Check provider settings and model name.',
  'server_error' => '$providerName server error. Try again later.',
  'http_error' =>
    statusCode == null
        ? '$providerName returned an HTTP error.'
        : '$providerName returned HTTP $statusCode.',
  'malformed_response' => '$providerName returned a malformed response.',
  'network_error' =>
    "Couldn't connect to $providerName. Check your internet connection and try again.",
  _ => '$providerName request failed. Check provider settings and try again.',
};

String _safeErrorText(String value) {
  final compact = value
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.length <= 240) return compact;
  return '${compact.substring(0, 240)}...';
}

String _stripDartPrefix(String value, String prefix) =>
    value.startsWith(prefix) ? value.substring(prefix.length) : value;
