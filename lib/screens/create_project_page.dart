import 'package:flutter/material.dart';
import '../styles/styles.dart';
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
        backgroundColor: AppColors.background,
        toolbarHeight: 0,
      ),
      backgroundColor: AppColors.background,
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
