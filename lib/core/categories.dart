import 'package:flutter/material.dart';
import 'models.dart';

/// Spending categories offered everywhere a category is picked.
class SpendCategory {
  const SpendCategory(this.name, this.icon, this.color, this.keywords);
  final String name;
  final IconData icon;
  final Color color;
  final List<String> keywords;
}

const uncategorized = 'Uncategorized';

const expenseCategories = [
  SpendCategory('Food', Icons.restaurant_rounded, Color(0xffe0874b), [
    '7-eleven',
    '7 eleven',
    'seven',
    'cafe',
    'coffee',
    'amazon',
    'starbucks',
    'restaurant',
    'food',
    'kfc',
    'mcdonald',
    'mk ',
    'bakery',
    'tea',
    'noodle',
    'grabfood',
    'lineman',
    'foodpanda',
    'robinhood',
    'shabu',
    'bbq',
    'pizza',
    'ร้านอาหาร',
    'กาแฟ',
    'อาหาร',
    'ဆိုင်',
    'စားသောက်',
    'လက်ဖက်ရည်',
  ]),
  SpendCategory(
    'Groceries',
    Icons.local_grocery_store_rounded,
    Color(0xff5aa469),
    [
      'lotus',
      'big c',
      'bigc',
      'makro',
      'tops',
      'villa market',
      'family mart',
      'familymart',
      'lawson',
      'cj ',
      'market',
      'supermarket',
      'city mart',
      'citymart',
      'ocean',
      'ตลาด',
      'ဈေး',
    ],
  ),
  SpendCategory('Transport', Icons.directions_bus_rounded, Color(0xff4f86c6), [
    'grab',
    'bolt',
    'bts',
    'mrt',
    'taxi',
    'airport',
    'rabbit',
    'bus',
    'train',
    'ptt',
    'shell',
    'bangchak',
    'esso',
    'caltex',
    'petrol',
    'fuel',
    'parking',
    'airasia',
    'nok air',
    'thai lion',
    'ရထား',
    'ကား',
    'ဓာတ်ဆီ',
    'แท็กซี่',
  ]),
  SpendCategory('Shopping', Icons.shopping_bag_rounded, Color(0xffc56aa8), [
    'shopee',
    'lazada',
    'central',
    'uniqlo',
    'h&m',
    'zara',
    'mall',
    'robinson',
    'emporium',
    'siam',
    'ikea',
    'watsons',
    'boots',
    'eveandboy',
    'apple',
    'jd central',
    'tiktok shop',
    'ช้อป',
  ]),
  SpendCategory('Bills', Icons.receipt_long_rounded, Color(0xff8a79c9), [
    'ais',
    'dtac',
    'mpt',
    'ooredoo',
    'atom',
    'mytel',
    'electric',
    'pea',
    'mea',
    'water',
    'pwa',
    'mwa',
    'internet',
    'fiber',
    'netflix',
    'spotify',
    'youtube',
    'icloud',
    'insurance',
    'rent',
    'ค่าไฟ',
    'ค่าน้ำ',
    'မီတာ',
    'ဖုန်းဘေ',
  ]),
  SpendCategory('Health', Icons.favorite_rounded, Color(0xffd65b5b), [
    'hospital',
    'clinic',
    'pharmacy',
    'drug',
    'dental',
    'bumrungrad',
    'bangkok hospital',
    'samitivej',
    'fascino',
    'โรงพยาบาล',
    'ร้านยา',
    'ဆေး',
  ]),
  SpendCategory(
    'Family & transfers',
    Icons.people_alt_rounded,
    Color(0xff3e9e9a),
    ['family', 'mom', 'mother', 'father', 'dad', 'အမေ', 'အဖေ', 'မိသားစု'],
  ),
  SpendCategory(
    'Other expenses',
    Icons.more_horiz_rounded,
    Color(0xff8c9a92),
    [],
  ),
];

const incomeCategories = ['Salary', 'Extra income', 'Gift', 'Other income'];

SpendCategory categoryStyle(String name) => expenseCategories.firstWhere(
  (c) => c.name == name,
  orElse: () => const SpendCategory(
    uncategorized,
    Icons.label_outline_rounded,
    Color(0xff9aa69f),
    [],
  ),
);

/// Normalises a merchant/receiver name so small OCR differences still match.
String merchantKey(String receiver) =>
    receiver.toLowerCase().replaceAll(RegExp(r'[^a-z0-9฀-๿က-႟]+'), ' ').trim();

/// Guesses a category for an expense. Categories the user chose before for
/// the same receiver win over keyword rules.
String? guessCategory(Slip s, Map<String, dynamic> memory) {
  if (s.direction != Direction.expense) return null;
  final key = merchantKey(s.receiver);
  if (key.isNotEmpty && memory[key] is String) return memory[key];
  final text = ' ${s.receiver} ${s.description} ${s.type} '.toLowerCase();
  for (final c in expenseCategories) {
    if (c.keywords.any((k) => text.contains(k))) return c.name;
  }
  return null;
}
