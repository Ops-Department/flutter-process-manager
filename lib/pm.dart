import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';

// An enum to represent the state of a process
enum ProcessManagerStatus {
  running,
  exited,
  terminated,
}

/// A class that holds all state and streams for a single command-line process.
class ProcessManagerInfo {
  final String id;
  final String command;
  final int pid;
  ProcessManagerStatus status;
  int? exitCode;
  String? lastOutputLine;
  bool isErrorOutput = false;
  final List<String> stdoutLines = [];
  final List<String> stderrLines = [];

  final Completer<int?> _exitCodeCompleter = Completer<int?>();
  final ProcessManagerService _service; // Reference to the parent service

  ProcessManagerInfo({
    required this.id,
    required this.command,
    required this.pid,
    required ProcessManagerService service, // Service instance is now required
    this.status = ProcessManagerStatus.running,
  }) : _service = service;

  /// A Future that completes with the exit code when the process terminates.
  Future<int?> get exitCodeFuture => _exitCodeCompleter.future;

  // Called by the service to clean up resources when the process is done.
  void dispose() {
    // Complete the exit code future if not already completed
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(exitCode);
    }
  }

  /// Stops this specific process by calling the parent service's stop method.
  bool stop() {
    return _service.stopProcess(id);
  }
}

/// A service for managing and monitoring command-line processes.
/// This service is designed to be instantiated once and reused.
class ProcessManagerService {
  final _uuid = const Uuid();
  final Map<String, ProcessManagerInfo> _activeProcesses = {};

  /// Starts a new command-line process.
  /// Returns a unique ID for the new process.
  ///
  /// The optional [onStdout] and [onStderr] callbacks allow for immediate
  /// handling of process output.
  Future<ProcessManagerInfo> startProcess(
    String fullCommand, {
    void Function(ProcessManagerInfo, String)? onStdout,
    void Function(ProcessManagerInfo, String)? onStderr,
    void Function(ProcessManagerInfo)? onExit,
  }) async {
    final parts = fullCommand.split(' ');
    final executable = parts.first;
    final arguments = parts.sublist(1);
    final processId = _uuid.v4();

    try {
      final process = await Process.start(executable, arguments);
      final newProcessInfo = ProcessManagerInfo(
        id: processId,
        command: fullCommand,
        pid: process.pid,
        service: this,
      );
      _activeProcesses[processId] = newProcessInfo;

      // Pipe stdout to the ProcessInfo's content buffer and call the optional callback
      process.stdout.transform(const Utf8Decoder()).listen(
        (data) {
          newProcessInfo.isErrorOutput = false;
          newProcessInfo.stdoutLines.add(data.trim());
          newProcessInfo.lastOutputLine = data.trim();
          onStdout?.call(newProcessInfo, data);
        },
        onError: (e) {
          newProcessInfo.isErrorOutput = true;
          newProcessInfo.stderrLines.add('Stream error: $e');
          newProcessInfo.lastOutputLine = 'Stream error: $e';
          onStderr?.call(newProcessInfo, 'Stream error: $e');
        },
      );


      // Pipe stderr to the ProcessInfo's content buffer and call the optional callback
      process.stderr.transform(const Utf8Decoder()).listen(
        (data) {
          newProcessInfo.isErrorOutput = true;
          newProcessInfo.stderrLines.add(data.trim());
          newProcessInfo.lastOutputLine = data.trim();
          onStderr?.call(newProcessInfo, data);
        },
        onError: (e) {
          newProcessInfo.isErrorOutput = true;
          newProcessInfo.stderrLines.add('Stream error: $e');
          newProcessInfo.lastOutputLine = 'Stream error: $e';
          onStderr?.call(newProcessInfo, 'Stream error: $e');
        },
      );

      // Handle process exit.
      process.exitCode.then((exitCode) {
        newProcessInfo.status = ProcessManagerStatus.exited;
        newProcessInfo.exitCode = exitCode;
        if (!newProcessInfo._exitCodeCompleter.isCompleted) {
          newProcessInfo._exitCodeCompleter.complete(exitCode);
        }
        _activeProcesses.remove(processId);
        newProcessInfo.dispose();
        onExit?.call(newProcessInfo);
      }).catchError((e) {
        newProcessInfo.status = ProcessManagerStatus.exited;
        newProcessInfo.exitCode = -1;
        if (!newProcessInfo._exitCodeCompleter.isCompleted) {
          newProcessInfo._exitCodeCompleter.complete(-1);
        }
        _activeProcesses.remove(processId);
        newProcessInfo.dispose();
        onExit?.call(newProcessInfo);
      });

      return newProcessInfo;
    } catch (e) {
      final processInfo = ProcessManagerInfo(
        id: processId,
        command: fullCommand,
        pid: -1,
        status: ProcessManagerStatus.exited,
        service: this,
      );
      processInfo.lastOutputLine = 'Failed to start process: $e';
      processInfo.isErrorOutput = true;
      processInfo.exitCode = -1;
      processInfo._exitCodeCompleter.complete(-1);
      _activeProcesses[processId] = processInfo;
      return processInfo;
    }
  }

  /// Stops a running process using its unique ID.
  /// Returns true if the process was found and killed, false otherwise.
  bool stopProcess(String processId) {
    return _stopProcess(processId, isTerminatedByUser: true);
  }

  // Private method with the unified logic for stopping a process.
  bool _stopProcess(String processId, {bool isTerminatedByUser = false}) {
    final processInfo = _activeProcesses[processId];
    if (processInfo != null && processInfo.status == ProcessManagerStatus.running) {
      final exitCode = isTerminatedByUser ? -1 : null;
      final message = isTerminatedByUser ? 'Process terminated by user' : 'Process stopped';

      // Update the state of the process
      processInfo.status = ProcessManagerStatus.terminated;
      processInfo.lastOutputLine = message;
      processInfo.isErrorOutput = false;
      processInfo.exitCode = exitCode;
      processInfo._exitCodeCompleter.complete(exitCode);

      // Actually kill the process
      final didKill = Process.killPid(processInfo.pid);

      // Clean up the service's state
      processInfo.dispose();
      _activeProcesses.remove(processId);
      return didKill;
    }
    return false;
  }
  
  /// Gets the ProcessInfo object for a specific process ID.
  /// Returns null if the process is not found.
  ProcessManagerInfo? getProcessInfo(String processId) {
    return _activeProcesses[processId];
  }

  /// Disposes of the service and all its managed resources.
  void dispose() {
    for (var processInfo in _activeProcesses.values) {
      processInfo.dispose();
    }
    _activeProcesses.clear();
  }
}
