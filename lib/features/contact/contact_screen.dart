import 'package:flutter/material.dart';
import '../../core/services/contact_service.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _channelController = TextEditingController();
  String _type = 'general';
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ContactService.sendMessage(
        type: _type,
        message: _messageController.text,
        channelInfo: _type == 'broken_link' ? _channelController.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رسالتك، شكراً لك')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال الرسالة، تحقق من الإنترنت وحاول مرة أخرى')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل معنا')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.support_agent_outlined, color: accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'راسلنا لأي استفسار أو رابط بث معطوب، وبنرد عليك بأقرب وقت.',
                      style: TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('نوع الرسالة', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'general',
                    label: Text('استفسار عام'),
                    icon: Icon(Icons.chat_bubble_outline, size: 17)),
                ButtonSegment(
                    value: 'broken_link',
                    label: Text('رابط معطوب'),
                    icon: Icon(Icons.link_off, size: 17)),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 20),
            if (_type == 'broken_link') ...[
              TextFormField(
                controller: _channelController,
                decoration: const InputDecoration(
                  labelText: 'اسم القناة أو القسم المتعلق (اختياري)',
                  prefixIcon: Icon(Icons.live_tv_outlined),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _messageController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: _type == 'broken_link' ? 'صف المشكلة بالتفصيل' : 'رسالتك',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 100),
                  child: Icon(Icons.message_outlined),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 5) {
                  return 'اكتب رسالة لا تقل عن 5 أحرف';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 19),
                label: Text(_sending ? 'جاري الإرسال…' : 'إرسال'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
