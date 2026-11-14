import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Daily quote data model patterned after Hitokoto (`hitokoto`, `from`, `from_who`)
/// with an offline curated pool and optional online fetch fallback.
@immutable
class DailyQuote {
  const DailyQuote({
    required this.text,
    required this.source,
    this.author,
    this.isOnline = false,
  });

  final String text;
  final String source;
  final String? author;
  final bool isOnline;

  String get attribution {
    final cleanSource = source.trim();
    final cleanAuthor = author?.trim();
    if (cleanAuthor != null &&
        cleanAuthor.isNotEmpty &&
        cleanSource.isNotEmpty) {
      return '$cleanSource · $cleanAuthor';
    }
    if (cleanSource.isNotEmpty) return cleanSource;
    if (cleanAuthor != null && cleanAuthor.isNotEmpty) return cleanAuthor;
    return '日课拾句';
  }

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  static DailyQuote? tryFromHitokotoJson(Map<String, dynamic> json) {
    final rawText = json['hitokoto'];
    if (rawText is! String) return null;
    final cleanText = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanText.isEmpty ||
        cleanText.length > 120 ||
        _controlChars.hasMatch(cleanText)) {
      return null;
    }
    final rawSource = json['from'];
    final cleanSource = rawSource is String
        ? rawSource.replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    if (_controlChars.hasMatch(cleanSource)) return null;
    final rawAuthor = json['from_who'];
    final cleanAuthor = rawAuthor is String
        ? rawAuthor.replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    if (_controlChars.hasMatch(cleanAuthor)) return null;
    return DailyQuote(
      text: cleanText,
      source: cleanSource.isEmpty ? '一言' : cleanSource,
      author: cleanAuthor.isEmpty ? null : cleanAuthor,
      isOnline: true,
    );
  }
}

typedef HitokotoFetcher = Future<DailyQuote?> Function();

final quoteServiceProvider = Provider<QuoteService>((_) => const QuoteService());

/// Provides offline-first random quotes and optional HTTPS Hitokoto fetches.
class QuoteService {
  const QuoteService({this.fetcher});

  static final Uri hitokotoUri = Uri.parse('https://v1.hitokoto.cn/?encode=json');
  static const int _maxResponseBytes = 16 * 1024;

  final HitokotoFetcher? fetcher;

  static const List<DailyQuote> localQuotes = [
    DailyQuote(text: '大医精诚，止于至善。', source: '备急千金要方', author: '孙思邈'),
    DailyQuote(text: '博观而约取，厚积而薄发。', source: '稼说送张琥', author: '苏轼'),
    DailyQuote(text: '行到水穷处，坐看云起时。', source: '终南别业', author: '王维'),
    DailyQuote(text: '山中习静观朝槿，松下清斋折露葵。', source: '积雨辋川庄作', author: '王维'),
    DailyQuote(text: '且将新火试新茶，诗酒趁年华。', source: '望江南', author: '苏轼'),
    DailyQuote(text: '读书之法，在循序而渐进，熟读而精思。', source: '朱子语类', author: '朱熹'),
    DailyQuote(text: '知者不惑，仁者不忧，勇者不惧。', source: '论语 · 子罕'),
    DailyQuote(text: '非学无以广才，非志无以成学。', source: '诫子书', author: '诸葛亮'),
    DailyQuote(text: '静而后能安，安而后能虑，虑而后能得。', source: '大学'),
    DailyQuote(text: '上善若水，水善利万物而不争。', source: '道德经'),
    DailyQuote(text: '云无心以出岫，鸟倦飞而知还。', source: '归去来兮辞', author: '陶渊明'),
    DailyQuote(text: '春风得意马蹄疾，一日看尽长安花。', source: '登科后', author: '孟郊'),
    DailyQuote(text: '月光所照，皆是故乡；心之所向，皆是坦途。', source: '日课拾句'),
    DailyQuote(text: '不积跬步，无以至千里；不积小流，无以成江海。', source: '荀子 · 劝学'),
    DailyQuote(text: '万物静观皆自得，四时佳兴与人同。', source: '秋日偶成', author: '程颢'),
    DailyQuote(text: '清风两袖朝天去，不带江南一寸棉。', source: '诗话拾遗'),
    DailyQuote(text: '心静即声淡，其间无古今。', source: '船子和尚偈'),
    DailyQuote(text: '松风煮茗，竹雨谈诗，日常亦清欢。', source: '日课拾句'),
    DailyQuote(text: '一寸光阴一寸金，寸金难买寸光阴。', source: '增广贤文'),
    DailyQuote(text: '采菊东篱下，悠然见南山。', source: '饮酒 · 其五', author: '陶渊明'),
    DailyQuote(text: '敏而好学，不耻下问。', source: '论语 · 公冶长'),
    DailyQuote(text: '沉舟侧畔千帆过，病树前头万木春。', source: '酬乐天扬州初逢席上见赠', author: '刘禹锡'),
    DailyQuote(text: '天行健，君子以自强不息。', source: '周易'),
    DailyQuote(text: '今日宜静气凝神，把每一堂课走实。', source: '日课拾句'),
  ];

  DailyQuote pickLocal({math.Random? random, String? excludeText}) {
    final rng = random ?? math.Random();
    if (localQuotes.length == 1) return localQuotes.first;
    final candidates = excludeText == null
        ? localQuotes
        : localQuotes.where((q) => q.text != excludeText).toList();
    final pool = candidates.isEmpty ? localQuotes : candidates;
    return pool[rng.nextInt(pool.length)];
  }

  Future<DailyQuote> nextQuote({
    required bool allowOnline,
    math.Random? random,
    String? excludeText,
  }) async {
    if (!allowOnline) {
      return pickLocal(random: random, excludeText: excludeText);
    }
    try {
      final online = await (fetcher ?? fetchHitokoto)();
      if (online != null && online.text != excludeText) {
        return online;
      }
      if (online != null && localQuotes.isEmpty) {
        return online;
      }
    } catch (_) {
      // Seamless local fallback when offline, timed out, or malformed response.
    }
    return pickLocal(random: random, excludeText: excludeText);
  }

  static Future<DailyQuote?> fetchHitokoto() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(hitokotoUri)
          .timeout(const Duration(seconds: 4));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 4))) {
        if (builder.length + chunk.length > _maxResponseBytes) return null;
        builder.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      if (decoded is! Map<String, dynamic>) return null;
      return DailyQuote.tryFromHitokotoJson(decoded);
    } finally {
      client.close(force: true);
    }
  }
}
