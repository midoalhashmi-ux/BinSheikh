import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/player_settings.dart';
import 'content_service.dart';

/// تطبيق المحتوى لا يملك رابط البث. يرسل معرف القناة فقط إلى المشغل الخارجي.
///
/// آلية الاستدعاء (بالترتيب):
/// 1) Intent صريح موجّه لاسم حزمة المشغل بالضبط (settings/player.androidPackage) —
///    يضمن فتح تطبيق المشغل تحديداً بدون تعارض أو نافذة اختيار مع تطبيقات أخرى.
/// 2) إن فشل (المشغل غير مثبت أو اسم الحزمة غير مضبوط): رابط داخلي عام
///    (deepLinkScheme) كخطة بديلة.
/// 3) إن فشل الاثنان: عرض رسالة تحميل المشغل من المتجر.
class PlayerLauncher {
  // يحمي من استدعاء مزدوج خلال وقت قصير جداً (ضغطة سريعة مكررة، أو حدث لمس
  // مسجَّل مرتين من النظام) — كان يتسبب بإرسال رابطين عميقين متتاليين
  // لتطبيق المشغل لنفس القناة، فيفتح المشغل شاشة مشاهدة ثم يستبدلها فوراً
  // بأخرى قبل ما تكتمل حتى محاولة تحميل المصدر الأولى.
  static DateTime? _lastOpenAt;

  static Future<void> openChannel(
    BuildContext context,
    String channelId, {
    String? categoryId,
    String? title,
  }) async {
    final now = DateTime.now();
    if (_lastOpenAt != null && now.difference(_lastOpenAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastOpenAt = now;
    unawaited(ContentService.recordView(channelId: channelId, categoryId: categoryId));

    PlayerSettings settings;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      settings = PlayerSettings.fromMap(snapshot.data());
    } catch (_) {
      settings = PlayerSettings.fromMap(null);
    }

    final scheme = settings.deepLinkScheme.trim().replaceAll('://', '');
    // المشغّل (sports_player/main.dart) يقرأ title= من الرابط العميق فعلياً
    // ويعرضه أعلى شاشة المشاهدة — لكن هذا الاستدعاء لم يكن يرسله إطلاقاً
    // (اسم القناة/الفيلم/الحلقة متوفر دائماً بـChannelCard.channel.title
    // ولم يكن يُمرَّر أصلاً)، فتبقى الشاشة بلا عنوان ظاهر دائماً.
    final playerUri = Uri(
      scheme: scheme,
      host: 'play',
      queryParameters: {
        'channelId': channelId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );

    if (Platform.isAndroid && settings.androidPackage.trim().isNotEmpty) {
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: playerUri.toString(),
          package: settings.androidPackage.trim(),
        );
        await intent.launch();
        return;
      } catch (_) {
        // المشغل غير مثبت بهذا الاسم بالضبط، أو الجهاز رفض الـ Intent الصريح.
        // نكمل للخطة البديلة (الرابط الداخلي العام) بدل الفشل مباشرة.
      }
    }

    try {
      final opened = await launchUrl(
        playerUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // إذا لم يكن المشغل مثبتاً نعرض خيار تثبيته بدلاً من إظهار خطأ تقني.
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تطبيق المشغل مطلوب'),
        content: const Text(
          'لم يتم العثور على تطبيق المشغل. ثبّته أولاً ثم ارجع وافتح القناة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: settings.storeUrl.isEmpty
                ? null
                : () async {
                    await launchUrl(
                      Uri.parse(settings.storeUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
            child: const Text('تحميل المشغل'),
          ),
        ],
      ),
    );
  }
}
