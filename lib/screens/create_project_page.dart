import 'package:flutter/material.dart';
import '../widgets/create_project_sheet.dart';

class CreateProjectPage extends StatefulWidget {
  final bool showCloseButton;
  final bool isFullPage;

  const CreateProjectPage({
    super.key,
    this.showCloseButton = true,
    this.isFullPage = false,
  });

  @override
  CreateProjectPageState createState() => CreateProjectPageState();
}

class CreateProjectPageState extends State<CreateProjectPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff121212),
        toolbarHeight: 0,
      ),
      backgroundColor: const Color(0xff121212),
      body: CreateProjectSheet(
        isDefaultProject: false,
        showCloseButton: widget.showCloseButton,
        isFullPage: widget.isFullPage,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
