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
    if (error.details != null) {
      return error.details!.copyWith(providerName: name).toDisplayText();
    }
    return switch (error.kind) {
      'malformed_endpoint' =>
        'Provider URL is invalid. Enter a valid http:// or https:// URL.',
      'no_network' =>
        "Couldn't connect to $name. Check your internet connection and try again.",
      'dns_failure' =>
        "Couldn't find $name. Check your internet connection and provider URL.",
      'tls_failure' =>
        "Couldn't verify the secure connection to $name. Check device date/time and network settings.",
      'timeout' => '$name did not respond in time. Try again.',
      'auth_error' => '$name rejected the request. Check the API key.',
      'oauth_error' => '$name sign-in failed. Try again.',
      'rate_limited' => '$name rate limit reached. Try again later.',
      'context_length' =>
        '$name rejected the request because context is too large.',
      'bad_request' =>
        '$name rejected the request. Check provider settings and model name.',
      'server_error' => '$name server error. Try again later.',
      'http_error' =>
        error.statusCode == null
            ? '$name returned an HTTP error.'
            : '$name returned HTTP ${error.statusCode}.',
      'malformed_response' => '$name returned a malformed response.',
      'network_error' =>
        "Couldn't connect to $name. Check your internet connection and try again.",
      _ => '$name request failed. Check provider settings and try again.',
    };
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
