import 'package:flutter/material.dart';
import '../styles/styles.dart';

class FAQPage extends StatelessWidget {
  const FAQPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('F.A.Q.')),
      body: Container(
        color: AppColors.overlay.withValues(alpha: 0.54),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: const [
            FAQItem(
              question: "Does AgeLapse store or collect my data?",
              answer:
                  "AgeLapse does not collect or store any data. As AgeLapse runs locally on"
                  " your device, your data is never transmitted over a network. ",
            ),
            FAQItem(
              question: "Is AgeLapse open-source?",
              answer:
                  "Yes! We are proud to be 100% open-source and free, forever. The "
                  "source code can be viewed at: github.com/hugocornellier/agelapse \n\nA note to developers: We"
                  " welcome PRs, bug reports or feature suggestions. Get in touch! ",
            ),
            FAQItem(
              question: "How does facial detection and stabilization work?",
              answer:
                  "Our app uses Google MLKit to detect facial landmarks such as the eyes, nose, and mouth. "
                  "By identifying these key points, we can ensure that they remain in the same position "
                  "relative to each other across all photos. This process of stabilization aligns the landmarks "
                  "consistently, resulting in a smooth and cohesive time-lapse video.",
            ),
          ],
        ),
      ),
    );
  }
}

class FAQItem extends StatelessWidget {
  final String question;
  final String answer;

  const FAQItem({super.key, required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: const TextStyle(
                fontSize: AppTypography.lg,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(answer, style: const TextStyle(fontSize: AppTypography.md)),
          ],
        ),
      ),
    );
  }
}
