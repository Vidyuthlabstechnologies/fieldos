/// Reads a spoken or typed site report and pulls out what a DPR needs: how
/// many people worked and what the weather was. [detectIssues] in
/// dpr_intake.dart uses the same reader for problems worth raising.
///
/// Works in English, Hindi and Telugu (plus Hinglish typed in English
/// letters, and digits in every Indian script), entirely on the phone: no
/// network, no cost, and the same answer every time, so it can be tested.
/// Speech recognisers write most numbers as digits ("20 मजदूर", "20 మంది"),
/// so digits are the main path; number words are covered for the common
/// cases.
library;

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

/// One word of the report, with its place in the original text so a
/// detected issue can quote the words that raised it.
class ReportToken {
  ReportToken(this.raw, this.norm, this.start, this.end);

  /// The word as it was written.
  final String raw;

  /// Lower case, Indian-script digits as 0-9, nukta and chandrabindu folded
  /// (so "मज़दूर" and "मजदूर", "पाँच" and "पांच" read the same).
  final String norm;
  final int start;
  final int end;

  /// The number this token starts, if it starts one ("twenty five" gives 25
  /// on "twenty"), and how many tokens that number spans.
  int? value;
  int span = 1;

  bool get isLatin => norm.isNotEmpty && norm.codeUnitAt(0) < 0x0900;
}

final _wordOrNumber = RegExp(r'\p{Nd}+|[\p{L}\p{M}]+', unicode: true);

/// Splits [text] into words and numbers, with number words resolved.
List<ReportToken> tokenizeReport(String text) {
  final clean = stripJoiners(text);
  final tokens = <ReportToken>[];
  for (final m in _wordOrNumber.allMatches(clean)) {
    tokens.add(ReportToken(m.group(0)!, normalizeWord(m.group(0)!), m.start, m.end));
  }
  _resolveNumbers(tokens);
  return tokens;
}

/// Zero-width joiners split words in two otherwise ("మ్యాన్‌పవర్").
String stripJoiners(String text) => text.replaceAll(RegExp('[​-‍⁠﻿]'), '');

/// The digit zero of each Indian script, so ३ and ౩ read as 3.
const _digitZeros = [0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66];

String normalizeWord(String word) {
  final out = StringBuffer();
  for (final r in stripJoiners(word).runes) {
    var handled = false;
    for (final zero in _digitZeros) {
      if (r >= zero && r <= zero + 9) {
        out.writeCharCode(0x30 + r - zero);
        handled = true;
        break;
      }
    }
    if (handled) continue;
    // Nukta (Devanagari, Bengali, Gurmukhi, Gujarati, Odia, Kannada).
    if (r == 0x093C || r == 0x09BC || r == 0x0A3C || r == 0x0ABC || r == 0x0B3C || r == 0x0CBC) continue;
    // Chandrabindu reads as anusvara: पाँच = पांच.
    if (r == 0x0901) {
      out.writeCharCode(0x0902);
      continue;
    }
    out.writeCharCode(r);
  }
  return out.toString().toLowerCase();
}

/// Whether [token] (normalized) matches keyword [kw] (normalized).
///
/// A trailing `*` makes the keyword a prefix ("వర్షం*" matches "వర్షంలో",
/// "in the rain"), which Telugu and the other Dravidian languages need
/// because they join case endings onto the word. Without it the whole word
/// must match, so "rain" is not found in "drain" and "mason" not in
/// "masonry"; English keywords also match a plain plural.
bool tokenMatches(String token, String kw) {
  if (kw.endsWith('*')) return token.startsWith(kw.substring(0, kw.length - 1));
  if (token == kw) return true;
  if (kw.codeUnitAt(0) < 0x0900) return token == '${kw}s' || token == '${kw}es';
  return false;
}

/// Whether a comma, full stop or similar sits between two words, which
/// ends a phrase: in "Total 30, slab casting" the 30 is not 30 slabs.
bool punctuationBetween(String text, ReportToken a, ReportToken b, {bool allowColon = false}) {
  if (b.start <= a.end) return false;
  final gap = text.substring(a.end, b.start);
  return RegExp(allowColon ? r'[,.;!?।॥]' : r'[,.;:!?।॥]').hasMatch(gap);
}

/// A keyword or phrase, written naturally and normalized once.
class Keyword {
  Keyword(String text) : parts = text.split(' ').map(_normKw).toList();
  final List<String> parts;

  static String _normKw(String p) => p.endsWith('*') ? '${normalizeWord(p.substring(0, p.length - 1))}*' : normalizeWord(p);

  /// Whether this keyword starts at token [i].
  bool matchesAt(List<ReportToken> tokens, int i) {
    if (i + parts.length > tokens.length) return false;
    for (var k = 0; k < parts.length; k++) {
      if (!tokenMatches(tokens[i + k].norm, parts[k])) return false;
    }
    return true;
  }
}

List<Keyword> keywords(List<String> list) => list.map(Keyword.new).toList();

bool anyMatchAt(List<Keyword> kws, List<ReportToken> tokens, int i) => firstMatchAt(kws, tokens, i) != null;

Keyword? firstMatchAt(List<Keyword> kws, List<ReportToken> tokens, int i) {
  for (final k in kws) {
    if (k.matchesAt(tokens, i)) return k;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Negation
// ---------------------------------------------------------------------------

/// English says "no rain"; Hindi and Telugu say "बारिश नहीं", "వర్షం పడలేదు".
final _negBefore = {'no', 'not', 'without', 'never', 'nil', 'none', 'didn', 'wasn', 'weren', 'isn', 'aren', 'hasn', 'haven'};
final _negAfter = {'नहीं', 'नही', 'ना', 'न', 'बिना', 'लेदु', 'nahi', 'nahin', 'nhi', 'ledu', 'లేదు', 'లేవు', 'లేకుండా', 'కాలేదు'}
    .map(normalizeWord)
    .toSet();

/// Whether [norm] (a normalized word) says "not".
bool isNegationWord(String norm) =>
    _negBefore.contains(norm) || _negAfter.contains(norm) || norm.endsWith('లేదు') || norm.endsWith('లేవు');

/// Whether the word at [i] (spanning [len] tokens) is negated.
bool isNegated(List<ReportToken> tokens, int i, [int len = 1]) {
  for (var k = i - 2; k < i; k++) {
    if (k >= 0 && _negBefore.contains(tokens[k].norm)) return true;
  }
  for (var k = i + len; k < i + len + 2 && k < tokens.length; k++) {
    final t = tokens[k].norm;
    if (_negAfter.contains(t) || t.endsWith('లేదు') || t.endsWith('లేవు')) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

const _enNumbers = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40,
  'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
};

/// Hindi has a separate word for every number to a hundred.
final Map<String, int> _hiNumbers = () {
  const words = [
    'एक', 'दो', 'तीन', 'चार', 'पांच', 'छह', 'सात', 'आठ', 'नौ', 'दस',
    'ग्यारह', 'बारह', 'तेरह', 'चौदह', 'पंद्रह', 'सोलह', 'सत्रह', 'अठारह', 'उन्नीस', 'बीस',
    'इक्कीस', 'बाईस', 'तेईस', 'चौबीस', 'पच्चीस', 'छब्बीस', 'सत्ताईस', 'अट्ठाईस', 'उनतीस', 'तीस',
    'इकतीस', 'बत्तीस', 'तैंतीस', 'चौंतीस', 'पैंतीस', 'छत्तीस', 'सैंतीस', 'अड़तीस', 'उनतालीस', 'चालीस',
    'इकतालीस', 'बयालीस', 'तैंतालीस', 'चवालीस', 'पैंतालीस', 'छियालीस', 'सैंतालीस', 'अड़तालीस', 'उनचास', 'पचास',
    'इक्यावन', 'बावन', 'तिरपन', 'चौवन', 'पचपन', 'छप्पन', 'सत्तावन', 'अट्ठावन', 'उनसठ', 'साठ',
    'इकसठ', 'बासठ', 'तिरसठ', 'चौंसठ', 'पैंसठ', 'छियासठ', 'सड़सठ', 'अड़सठ', 'उनहत्तर', 'सत्तर',
    'इकहत्तर', 'बहत्तर', 'तिहत्तर', 'चौहत्तर', 'पचहत्तर', 'छिहत्तर', 'सतहत्तर', 'अठहत्तर', 'उन्यासी', 'अस्सी',
    'इक्यासी', 'बयासी', 'तिरासी', 'चौरासी', 'पचासी', 'छियासी', 'सत्तासी', 'अट्ठासी', 'नवासी', 'नब्बे',
    'इक्यानवे', 'बानवे', 'तिरानवे', 'चौरानवे', 'पचानवे', 'छियानवे', 'सत्तानवे', 'अट्ठानवे', 'निन्यानवे', 'सौ',
  ];
  final map = <String, int>{for (var i = 0; i < words.length; i++) normalizeWord(words[i]): i + 1};
  // Common other spellings.
  const variants = {'छः': 6, 'छे': 6, 'पन्द्रह': 15, 'अठाईस': 28, 'चौवालीस': 44, 'उनासी': 79};
  for (final e in variants.entries) {
    map[normalizeWord(e.key)] = e.value;
  }
  return map;
}();

/// Telugu: units and tens join ("ఇరవై ఐదు", 25), and people are counted
/// with their own words ("ముగ్గురు", three people).
final Map<String, int> _teUnits = {
  for (final e in {
    'ఒకటి': 1, 'ఒక': 1, 'ఒక్క': 1, 'ఒకరు': 1, 'ఒక్కరు': 1, 'రెండు': 2, 'ఇద్దరు': 2, 'మూడు': 3, 'ముగ్గురు': 3,
    'నాలుగు': 4, 'నలుగురు': 4, 'ఐదు': 5, 'అయిదు': 5, 'ఐదుగురు': 5, 'ఆరు': 6, 'ఆరుగురు': 6, 'ఏడు': 7,
    'ఏడుగురు': 7, 'ఎనిమిది': 8, 'తొమ్మిది': 9,
  }.entries)
    normalizeWord(e.key): e.value,
};
final Map<String, int> _teTeensAndTens = {
  for (final e in {
    'పది': 10, 'పదిమంది': 10, 'పదకొండు': 11, 'పన్నెండు': 12, 'పదమూడు': 13, 'పద్నాలుగు': 14, 'పదిహేను': 15,
    'పదహారు': 16, 'పదిహేడు': 17, 'పద్దెనిమిది': 18, 'పందొమ్మిది': 19, 'ఇరవై': 20, 'ముప్పై': 30, 'ముప్ఫై': 30,
    'నలభై': 40, 'నలబై': 40, 'యాభై': 50, 'యాబై': 50, 'అరవై': 60, 'డెబ్బై': 70, 'ఎనభై': 80, 'ఎనబై': 80,
    'తొంభై': 90, 'తొంబై': 90, 'వంద': 100, 'నూరు': 100,
  }.entries)
    normalizeWord(e.key): e.value,
};

void _resolveNumbers(List<ReportToken> t) {
  for (var i = 0; i < t.length; i++) {
    final w = t[i].norm;
    if (RegExp(r'^\d+$').hasMatch(w)) {
      if (w.length <= 5) t[i].value = int.parse(w);
      continue;
    }
    // English: "twenty five", "one hundred and ten", "a dozen".
    if (_enNumbers.containsKey(w) || ((w == 'a' || w == 'one') && i + 1 < t.length && t[i + 1].norm == 'dozen')) {
      var total = 0, current = 0, j = i;
      while (j < t.length) {
        final n = t[j].norm;
        if (_enNumbers.containsKey(n)) {
          current += _enNumbers[n]!;
        } else if (n == 'a' && j == i) {
          current = 1;
        } else if (n == 'hundred') {
          current = (current == 0 ? 1 : current) * 100;
        } else if (n == 'dozen') {
          current = (current == 0 ? 1 : current) * 12;
        } else if (n == 'and' && j + 1 < t.length && _enNumbers.containsKey(t[j + 1].norm) && current >= 100) {
          // "one hundred and ten"
        } else {
          break;
        }
        j++;
      }
      total += current;
      t[i].value = total;
      t[i].span = j - i;
      i = j - 1;
      continue;
    }
    if (_hiNumbers.containsKey(w)) {
      t[i].value = _hiNumbers[w];
      continue;
    }
    if (_teTeensAndTens.containsKey(w) || _teUnits.containsKey(w)) {
      var v = _teTeensAndTens[w] ?? _teUnits[w]!;
      var span = 1;
      final tens = _teTeensAndTens[w];
      if (tens != null && tens >= 20 && tens % 10 == 0 && i + 1 < t.length && _teUnits.containsKey(t[i + 1].norm)) {
        v += _teUnits[t[i + 1].norm]!;
        span = 2;
      }
      t[i].value = v;
      t[i].span = span;
      i += span - 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Manpower
// ---------------------------------------------------------------------------

/// Words for people in general: "20 workers", "15 लोग", "10 మంది".
final _peopleWords = keywords([
  'people', 'persons', 'person', 'men', 'women', 'staff', 'crew', 'worker', 'workmen', 'labour', 'labor',
  'labours', 'manpower', 'headcount', 'heads', 'hands', 'workforce', 'log', 'logon', 'aadmi', 'mandi',
  // Hindi
  'लोग', 'लोगों', 'आदमी', 'आदमियों', 'लेबर', 'वर्कर', 'वर्कर्स', 'कर्मचारी', 'श्रमिक', 'श्रमिकों', 'कामगार',
  'कामगारों', 'जन', 'व्यक्ति', 'मैनपावर',
  // Telugu
  'మంది', 'జనం', 'మనుషులు', 'మనుష్యులు', 'వర్కర్*', 'లేబర్*', 'కార్మికు*', 'సిబ్బంది*', 'మ్యాన్పవర్*', 'పనివాళ్ళు*',
  'పనివాళ్లు*',
  // Tamil, Kannada, Marathi, Bengali, Gujarati, Malayalam, Punjabi, Odia
  'பேர்', 'ஆட்கள்*', 'தொழிலாளர்*', 'ಜನ', 'ಜನರು', 'ಕಾರ್ಮಿಕ*', 'लोक', 'जण', 'জন', 'লোক', 'শ্রমিক*', 'લોકો', 'જણ',
  'કામદાર*', 'പേർ', 'തൊഴിലാളി*', 'ਬੰਦੇ', 'ਲੋਕ', 'ଜଣ', 'ଶ୍ରମିକ*',
]);

/// Counting words that say "people" and let the trade follow:
/// "10 మంది మేస్త్రీలు" is ten masons.
final _classifiers = keywords(['మంది', 'जन', 'जण', 'ಜನ', 'জন', 'જણ', 'ଜଣ', 'பேர்', 'പേർ', 'mandi']);

/// Trades and unskilled labour: "10 masons and 5 helpers" is 15 people.
final _tradeWords = keywords([
  'mason', 'helper', 'carpenter', 'bender', 'barbender', 'fitter', 'electrician', 'plumber', 'painter', 'welder',
  'operator', 'driver', 'mistri', 'mistry', 'mistries', 'mestri', 'mesthri', 'coolie', 'cooly', 'beldar', 'mazdoor',
  'majdoor', 'mazdur', 'labourer', 'laborer', 'tiler', 'polisher', 'rigger', 'scaffolder', 'khalasi', 'kooli',
  // Hindi
  'मजदूर', 'मजदूरों', 'मिस्त्री*', 'मिस्तरी*', 'राजमिस्त्री*', 'बेलदार*', 'हेल्पर*', 'कारीगर*', 'बढई*', 'प्लंबर*',
  'इलेक्ट्रीशियन*', 'पेंटर*', 'वेल्डर*', 'फिटर*', 'कुली*', 'ऑपरेटर*', 'ड्राइवर*', 'बेंडर*',
  // Telugu
  'కూలీ*', 'కూలి*', 'మేస్త్రీ*', 'మేస్త్రి*', 'హెల్పర్*', 'కార్పెంటర్*', 'వడ్రంగి*', 'ఎలక్ట్రీషియన్*', 'ప్లంబర్*',
  'పెయింటర్*', 'వెల్డర్*', 'ఫిట్టర్*', 'తాపీ*', 'బేల్దారి*', 'బెండర్*', 'ఆపరేటర్*', 'డ్రైవర్*',
  // Other Indian languages
  'கொத்தனார்*', 'சித்தாள்*', 'கூலி*', 'ಗಾರೆ*', 'ಕೂಲಿ*', 'ಮೇಸ್ತ್ರಿ*', 'मजूर*', 'गवंडी*', 'মজুর*', 'মিস্ত্রি*',
  'મજૂર*', 'કડિયા*', 'મિસ્ત્રી*', 'മേസ്തിരി*', 'കൂലി*', 'ਮਜ਼ਦੂਰ*', 'ਮਿਸਤਰੀ*', 'ମଜୁରିଆ*', 'ମିସ୍ତ୍ରୀ*',
]);

/// "manpower 25", "labour: 25", "मजदूर 25": a label then the count.
final _labelWords = keywords([
  'manpower', 'labour', 'labor', 'workers', 'headcount', 'strength', 'attendance', 'मैनपावर', 'लेबर', 'मजदूर',
  'हाजिरी', 'మ్యాన్పవర్', 'లేబర్', 'కూలీలు', 'హాజరు',
]);
final _linkWords = {'is', 'was', 'were', 'count', 'strength', 'total', 'around', 'about', 'approx', 'approximately',
  'nearly', 'of', 'कुल', 'थे', 'था', 'है', 'लगभग', 'మొత్తం', 'దాదాపు'}.map(normalizeWord).toSet();

/// "total 25", "कुल 25", "మొత్తం 25": the speaker gave the total.
final _totalWords = {'total', 'totally', 'altogether', 'overall', 'कुल', 'टोटल', 'మొత్తం', 'టోటల్', 'மொத்தம்',
  'ಒಟ್ಟು', 'एकूण', 'মোট', 'કુલ', 'ആകെ', 'ਕੁੱਲ', 'ମୋଟ'}.map(normalizeWord).toSet();

/// Words after a number that make it a time, a floor, an amount or a
/// quantity, never a headcount: "8 hours", "3rd floor", "50 bags".
final _unitWords = {
  'am', 'pm', 'hrs', 'hr', 'hour', 'hours', 'minute', 'minutes', 'mins', 'min', 'day', 'days', 'week', 'weeks',
  'month', 'months', 'floor', 'floors', 'storey', 'storeys', 'st', 'nd', 'rd', 'th', 'bag', 'bags', 'kg', 'kgs',
  'tonne', 'tonnes', 'ton', 'tons', 'mt', 'cum', 'cft', 'sqft', 'sft', 'sqm', 'rmt', 'm', 'mm', 'cm', 'ft', 'feet',
  'inch', 'inches', 'metre', 'metres', 'meter', 'meters', 'percent', 'rs', 'rupees', 'lakh', 'lakhs', 'crore',
  'truck', 'trucks', 'load', 'loads', 'trip', 'trips', 'litre', 'litres', 'liter', 'liters', 'brick', 'bricks',
  'block', 'blocks', 'room', 'rooms', 'column', 'columns', 'beam', 'beams', 'slab', 'slabs', 'unit', 'units',
  'flat', 'flats', 'house', 'houses', 'per', 'o', 'clock', 'times', 'nos', 'number', 'numbers',
  'बजे', 'घंटे', 'घंटा', 'दिन', 'मंजिल', 'बोरी', 'बोरियां', 'किलो', 'टन', 'फीट', 'मीटर', 'रुपये', 'रुपए', 'प्रतिशत', 'ट्रक',
  'प्रति', 'गुना',
  'గంటలు', 'గంటల', 'గంట', 'గంటలకు', 'రోజులు', 'రోజు', 'అంతస్తు', 'అంతస్తులు', 'బస్తాలు', 'బస్తా', 'కిలోలు', 'టన్నులు',
  'అడుగులు', 'మీటర్లు', 'రూపాయలు', 'శాతం', 'ట్రక్కులు', 'ఫ్లోర్', 'ప్రతి', 'లోడ్లు', 'ట్రిప్పులు',
}.map(normalizeWord).toSet();

/// Words before a number that make it money or a rate: "Rs 500",
/// "రోజుకు 500 కూలీ" (a wage of 500 a day).
final _moneyBefore = {'rs', 'inr', 'rupees', 'rupee', 'wage', 'wages', 'rate', 'daily', 'रुपये', 'रुपए', 'रोज', 'रोजाना',
  'प्रतिदिन', 'मजदूरी', 'రూ', 'రూపాయలు', 'రోజుకు', 'రోజుకి', 'జీతం'}.map(normalizeWord).toSet();

bool _isUnitAfter(String text, List<ReportToken> t, int i) {
  final last = t[i + t[i].span - 1];
  if (last.end < text.length && (text[last.end] == '%' || text[last.end] == '₹')) return true;
  final start = t[i].start;
  if (start > 0 && text[start - 1] == '₹') return true;
  if (i > 0 && _moneyBefore.contains(t[i - 1].norm)) return true;
  final next = i + t[i].span;
  return next < t.length && _unitWords.contains(t[next].norm) && !punctuationBetween(text, last, t[next]);
}

/// How many people worked, from a narrative like "12 masons and 8 helpers"
/// (20), "बीस मजदूर आए" (20) or "మొత్తం 25 మంది" (25). Null when the
/// report doesn't say.
///
/// The rule: an explicit total wins. Otherwise trades add up, and a general
/// count ("20 workers") that is at least that sum is taken as the total
/// that includes them ("20 workers: 12 masons, 8 helpers" is 20, not 40).
int? extractManpower(String text) {
  final clean = stripJoiners(text);
  final t = tokenizeReport(clean);
  final general = <int>{};
  final trades = <String, int>{};
  int? explicitTotal;

  bool isPeople(int j) => j >= 0 && j < t.length && t[j].value == null &&
      (firstMatchAt(_tradeWords, t, j) != null || firstMatchAt(_peopleWords, t, j) != null ||
          firstMatchAt(_labelWords, t, j) != null);
  final mentionsPeople = Iterable<int>.generate(t.length).any(isPeople);

  /// 'general', or 'trade:<keyword>' for the trade word at [j].
  String? kindAt(int j) {
    final trade = firstMatchAt(_tradeWords, t, j);
    if (trade != null) return 'trade:${trade.parts.first}';
    if (firstMatchAt(_peopleWords, t, j) != null || firstMatchAt(_labelWords, t, j) != null) return 'general';
    return null;
  }

  for (var i = 0; i < t.length; i++) {
    final v = t[i].value;
    if (v == null || v <= 0 || v > 5000) continue;
    if (_isUnitAfter(clean, t, i)) continue;
    final after = i + t[i].span;

    String? forward;
    // A number followed, within three words, by a people or trade word.
    for (var j = after; j < after + 3 && j < t.length; j++) {
      if (t[j].value != null || _unitWords.contains(t[j].norm)) break;
      if (punctuationBetween(clean, t[j - 1], t[j])) break;
      if (firstMatchAt(_classifiers, t, j) != null) {
        // "10 మంది మేస్త్రీలు": the trade follows the counting word.
        final trade = j + 1 < t.length ? firstMatchAt(_tradeWords, t, j + 1) : null;
        forward = trade != null ? 'trade:${trade.parts.first}' : 'general';
        break;
      }
      forward = kindAt(j);
      if (forward != null) break;
    }

    // Or a label before it: "manpower 25", "masons 8, helpers 4",
    // "labour count 25".
    String? backward;
    if (isPeople(i - 1) && !punctuationBetween(clean, t[i - 1], t[i], allowColon: true)) {
      backward = kindAt(i - 1);
    } else if (i > 1 && _linkWords.contains(t[i - 1].norm) && isPeople(i - 2) &&
        !punctuationBetween(clean, t[i - 2], t[i], allowColon: true)) {
      backward = kindAt(i - 2);
    }

    // "masons 5 helpers 10" names each group before its number; "5 masons
    // 10 helpers" after. When both fit, the word after decides only if no
    // number follows it.
    String? kind;
    if (backward != null && forward != null) {
      final labelStyle = after + 1 < t.length && t[after].value == null && t[after + 1].value != null &&
          !punctuationBetween(clean, t[after], t[after + 1], allowColon: true);
      kind = labelStyle ? backward : forward;
    } else {
      kind = forward ?? backward;
    }

    final markedTotal = (i > 0 && _totalWords.contains(t[i - 1].norm)) ||
        (i > 1 && _totalWords.contains(t[i - 2].norm)) ||
        (after < t.length && _totalWords.contains(t[after].norm));
    if (kind == null) {
      // "Total 25." in a report that talks about workers.
      if (markedTotal && mentionsPeople) explicitTotal ??= v;
      continue;
    }
    if (markedTotal) {
      explicitTotal ??= v;
    } else if (kind == 'general') {
      general.add(v);
    } else {
      trades['$kind:$v'] = v;
    }
    i = after - 1;
  }

  if (explicitTotal != null) return explicitTotal;
  final tradeSum = trades.values.fold<int>(0, (a, b) => a + b);
  final generalSum = general.fold<int>(0, (a, b) => a + b);
  if (general.isEmpty) return tradeSum == 0 ? null : tradeSum;
  if (tradeSum == 0) return generalSum;
  final maxGeneral = general.reduce((a, b) => a > b ? a : b);
  if (maxGeneral >= tradeSum) return maxGeneral;
  // "10 masons, 5 helpers and 3 other workers": separate groups.
  return tradeSum + generalSum;
}

// ---------------------------------------------------------------------------
// Weather
// ---------------------------------------------------------------------------

class _WeatherKind {
  _WeatherKind(this.label, List<String> words, {List<String> needsContext = const [], this.notBefore = const {}})
      : words = keywords(words),
        contextual = keywords(needsContext);
  final String label;
  final List<Keyword> words;

  /// Words that only mean weather near "weather" or "sky": "clear", "fine".
  final List<Keyword> contextual;

  /// "cold joint" and "hot mix" are concrete, not weather.
  final Set<String> notBefore;
}

/// In order of what matters most on site; the first two found are kept.
final _weatherKinds = [
  _WeatherKind('Storm', [
    'storm', 'stormy', 'thunderstorm', 'thunder', 'lightning', 'cyclone', 'hailstorm', 'hail', 'toofan', 'aandhi',
    'तूफान', 'आंधी', 'आंधियां', 'ओले', 'ओलावृष्टि', 'తుఫాను*', 'తుపాను*', 'ఉరుము*', 'పిడుగు*', 'వడగళ్ళ*', 'వడగండ్ల*',
  ]),
  _WeatherKind('Heavy rain', [
    'heavy rain', 'heavy rains', 'heavy raining', 'downpour', 'cloudburst', 'heavy showers', 'तेज बारिश',
    'भारी बारिश', 'मूसलाधार', 'तेज बरसात', 'భారీ వర్షం*', 'భారీ వర్షా*', 'కుండపోత*', 'జోరు వాన*', 'జోరుగా వర్షం*',
  ]),
  _WeatherKind('Light rain', [
    'drizzle', 'drizzling', 'light rain', 'light rains', 'light showers', 'slight rain', 'बूंदाबांदी', 'हल्की बारिश',
    'చినుకు*', 'జల్లు*', 'ముసురు*', 'తేలికపాటి వర్షం*', 'చిన్న వర్షం*',
  ]),
  _WeatherKind('Rain', [
    'rain', 'raining', 'rained', 'rainy', 'showers', 'baarish', 'barish', 'barsaat', 'varsham', 'vaana',
    'बारिश', 'बरसात', 'वर्षा', 'बरसा', 'बारिशों', 'వర్షం*', 'వర్షా*', 'వాన*', 'వర్షము*',
  ], notBefore: {'water', 'gun', 'coat', 'harvesting', 'pipe', 'pipes', 'proof', 'shed'}),
  _WeatherKind('Windy', [
    'windy', 'wind', 'winds', 'gusty', 'gusts', 'breezy', 'तेज हवा', 'तेज हवाएं', 'हवाएं', 'आंधी तूफान',
    'ఈదురుగాలు*', 'బలమైన గాలు*', 'గాలులు*', 'గాలివాన*',
  ], notBefore: {'load', 'loads', 'bracing', 'turbine'}),
  _WeatherKind('Fog', ['fog', 'foggy', 'mist', 'misty', 'haze', 'hazy', 'smog', 'कोहरा', 'धुंध', 'పొగమంచు*']),
  _WeatherKind('Cloudy', [
    'cloudy', 'clouds', 'cloud', 'overcast', 'badal', 'बादल', 'बादलों', 'बदली', 'మబ్బు*', 'మేఘా*', 'మేఘం*', 'మేఘావృత*',
  ]),
  _WeatherKind('Hot', [
    'hot', 'heat', 'heatwave', 'scorching', 'garmi', 'गर्मी', 'तेज धूप', 'लू', 'गरम', 'गर्म', 'వేడి*', 'ఎండలు*',
    'వడగాలు*', 'ఉష్ణోగ్రత*',
  ], notBefore: {'mix', 'water', 'wire', 'insulation', 'resistant', 'treatment'}),
  _WeatherKind('Sunny', ['sunny', 'sunshine', 'sun', 'dhoop', 'धूप', 'ఎండ', 'ఎండగా*', 'ఎండకాస*', 'ఎండ కాస*']),
  _WeatherKind('Clear', [
    'clear sky', 'clear skies', 'good weather', 'fine weather', 'साफ मौसम', 'मौसम साफ', 'మంచి వాతావరణం',
  ], needsContext: ['clear', 'fine', 'fair', 'good', 'pleasant', 'nice', 'साफ', 'अच्छा', 'सुहावना', 'బాగుంది', 'బాగా', 'ప్రశాంత*']),
  _WeatherKind('Cold', ['cold', 'chilly', 'chill', 'freezing', 'thand', 'ठंड', 'ठंडी', 'ठंडा', 'सर्दी', 'చలి*', 'చల్లగా*'],
      notBefore: {'joint', 'joints', 'storage', 'weld', 'weather'}),
  _WeatherKind('Humid', ['humid', 'humidity', 'muggy', 'sultry', 'उमस', 'ఉక్కపోత*']),
];

final _weatherContext = keywords(['weather', 'sky', 'skies', 'climate', 'mausam', 'मौसम', 'आसमान', 'వాతావరణం*', 'ఆకాశం*']);

/// The weather in a word or two ("Rain", "Cloudy, light rain"), always in
/// English so it prints on the PDF report. Null when the report doesn't say.
/// Negated mentions ("no rain", "बारिश नहीं हुई") don't count.
String? extractWeather(String text) {
  final t = tokenizeReport(text);
  final found = <String>[];
  for (final kind in _weatherKinds) {
    var hit = false;
    for (var i = 0; i < t.length && !hit; i++) {
      for (final kw in kind.words) {
        if (!kw.matchesAt(t, i)) continue;
        final next = i + kw.parts.length;
        if (next < t.length && kind.notBefore.contains(t[next].norm)) continue;
        if (isNegated(t, i, kw.parts.length)) continue;
        hit = true;
        break;
      }
      if (!hit && kind.contextual.isNotEmpty && anyMatchAt(kind.contextual, t, i)) {
        for (var j = i - 3; j <= i + 3; j++) {
          if (j >= 0 && j < t.length && j != i && anyMatchAt(_weatherContext, t, j)) {
            hit = !isNegated(t, i);
            break;
          }
        }
      }
    }
    if (hit) found.add(kind.label);
  }
  // Rain words overlap: keep the most specific, and say "rain" once.
  if (found.contains('Heavy rain') || found.contains('Light rain')) found.remove('Rain');
  if (found.contains('Heavy rain')) found.remove('Light rain');
  if (found.contains('Storm')) found.remove('Windy');
  if (found.contains('Hot')) found.remove('Sunny');
  if (found.length > 1) found.remove('Clear');
  if (found.isEmpty) return null;
  final top = found.take(2).toList();
  final label = top.length == 1 ? top.first : '${top[0]}, ${top[1].toLowerCase()}';
  return label.length > 50 ? label.substring(0, 50) : label;
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// The report as the engineer said it, tidied: spaces collapsed, an English
/// report starting with a capital and ending with a full stop.
String tidySummary(String text) {
  var s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty || isIndicScript(s)) return s;
  final first = s.codeUnitAt(0);
  if (first >= 0x61 && first <= 0x7A) s = '${s[0].toUpperCase()}${s.substring(1)}';
  s = s.replaceAll(RegExp(r'\bi\b'), 'I');
  final last = s.codeUnitAt(s.length - 1);
  final isLatinEnd = (last >= 0x41 && last <= 0x5A) || (last >= 0x61 && last <= 0x7A) || (last >= 0x30 && last <= 0x39);
  if (isLatinEnd) s = '$s.';
  return s;
}

/// Whether [text] is written mostly in an Indian script (so it needs the
/// phone's fonts, and can be offered a translation to English).
bool isIndicScript(String text) {
  var indic = 0, latin = 0;
  for (final r in text.runes) {
    if (r >= 0x0900 && r <= 0x0DFF) {
      indic++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      latin++;
    }
  }
  return indic > latin;
}
