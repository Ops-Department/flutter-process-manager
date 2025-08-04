import 'package:flutter/material.dart';
import 'dart:async';
import 'pm.dart'; 

void main() {
  runApp(const RunPromptApp());
}

class RunPromptApp extends StatelessWidget {
  const RunPromptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Run Prompt',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RunPromptPage(),
    );
  }
}

class RunPromptPage extends StatefulWidget {
  const RunPromptPage({super.key});

  @override
  State<RunPromptPage> createState() => _RunPromptPageState();
}

class _RunPromptPageState extends State<RunPromptPage> {
  final TextEditingController _commandController = TextEditingController();
  final ProcessManagerService _pm = ProcessManagerService();
  final Map<String, ProcessManagerInfo> _processes = {};
  
  @override
  void dispose() {
    _pm.dispose();
    super.dispose();
  }

  // This function spawns a new process based on user input
  Future<void> _spawnProcess(String fullCommand) async {
    // Handle empty command input
    if (fullCommand.trim().isEmpty) {
      _showErrorDialog('Command cannot be empty.');
      return;
    }

    // Call the service to start the process with callbacks for UI updates
    final processInfo = await _pm.startProcess(
      fullCommand,
      onStdout: (pmi, data) {
        // Update UI state on stdout
        final processInfo = pmi;
        processInfo.lastOutputLine = data.trim();
        processInfo.isErrorOutput = false;
        if (mounted) setState(() {});
      },
      onStderr: (pmi, data) {
        // Update UI state on stderr
        final processInfo = pmi;
        processInfo.lastOutputLine = data.trim();
        processInfo.isErrorOutput = true;
        if (mounted) setState(() {});
      },
      onExit: (pmi) {
        // Update UI state on exit
        print('Process exited: ${pmi.id} with exit code ${pmi.exitCode}');
        if (mounted) setState(() {});
      },
    );

    // If processId is not empty, it means the process was started successfully.
    if (processInfo.id.isNotEmpty) {
      setState(() {
        _processes[processInfo.id] = processInfo;
      });
    }
    
    // Clear the text field after submitting
    _commandController.clear();
  }

  // This function terminates a running process
  void _terminateProcess(String processId) {
    final processInfo = _processes[processId];
    if (processInfo != null && processInfo.status == ProcessManagerStatus.running) {
      _pm.stopProcess(processId);
      if (mounted) {
        setState(() {
          // The processInfo object is already updated by the service, so we just
          // need to trigger a rebuild.
        });
      }
    }
  }

  // This function shows a dialog with the process's output
  void _showOutputDialog(String processId) {
    final processInfo = _processes[processId];
    if (processInfo == null) return;
    
    showDialog(
      context: context,
      builder: (context) {
        // Since we are using callbacks to update state, we can use a StatefulBuilder
        // to listen for changes to the ProcessInfo object without needing streams.
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Output for: ${processInfo.command}'),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('STDOUT:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      Text(
                        processInfo.stdoutLines.join('\n'),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 16),
                      const Text('STDERR:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      Text(
                        processInfo.stderrLines.join('\n'),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      if (processInfo.stdoutLines.isEmpty && processInfo.stderrLines.isEmpty)
                        const Text('No output yet...'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Shows a simple error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Run Prompt'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _commandController,
              decoration: InputDecoration(
                labelText: 'Enter a command',
                hintText: 'e.g., ping google.com',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => _spawnProcess(_commandController.text),
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12.0)),
                ),
              ),
              onSubmitted: _spawnProcess,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _processes.length,
                itemBuilder: (context, index) {
                  final processInfo = _processes.values.elementAt(index);

                  // Determine the text to display in the subtitle
                  String subtitleText;
                  Color subtitleColor;

                  if (processInfo.lastOutputLine != null) {
                    final prefix = processInfo.isErrorOutput ? "ERROR" : "INFO";
                    subtitleText = '$prefix: ${processInfo.lastOutputLine}';
                    subtitleColor = processInfo.isErrorOutput ? Colors.red : Colors.green;
                  } else {
                    final statusText = processInfo.status == ProcessManagerStatus.running
                        ? 'Running...'
                        : 'Exited with code: ${processInfo.exitCode}';
                    subtitleText = 'PID: ${processInfo.pid} | $statusText';
                    subtitleColor = processInfo.status == ProcessManagerStatus.running ? Colors.green : (processInfo.exitCode == 0 ? Colors.green : Colors.red);
                    if (processInfo.status == ProcessManagerStatus.terminated) {
                      subtitleColor = Colors.orange;
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      leading: Icon(
                        processInfo.status == ProcessManagerStatus.running
                            ? Icons.settings_ethernet
                            : Icons.check_circle_outline,
                        color: processInfo.status == ProcessManagerStatus.running ? Colors.green : (processInfo.exitCode == 0 ? Colors.green : Colors.red),
                      ),
                      title: Text(processInfo.command),
                      subtitle: Text(
                        subtitleText,
                        style: TextStyle(color: subtitleColor),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // View output button
                          IconButton(
                            icon: const Icon(Icons.code),
                            tooltip: 'View Output',
                            onPressed: () => _showOutputDialog(processInfo.id),
                          ),
                          // Terminate button
                          if (processInfo.status == ProcessManagerStatus.running)
                            IconButton(
                              icon: const Icon(Icons.stop),
                              tooltip: 'Terminate Process',
                              color: Colors.red,
                              onPressed: () => _terminateProcess(processInfo.id),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
