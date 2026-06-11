import 'package:args/command_runner.dart';

import 'create_command.dart' show CreateCommand;
import 'init_command.dart' show InitCommand;

void main(List<String> arguments) async {
  final runner = CommandRunner<void>('cqrs_sync', 'CQRS offline sync boilerplate generator')
    ..addCommand(InitCommand())
    ..addCommand(CreateCommand());

  await runner.run(arguments);
}
