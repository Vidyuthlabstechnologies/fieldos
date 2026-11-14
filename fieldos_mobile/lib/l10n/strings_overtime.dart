/// Overtime pay on the wage sheet (the company's rate, and the US app's
/// state for California daily overtime), in every language the app has.
/// Spread into each language's table.
library;

const Map<String, String> overtimeHi = {
  'Overtime pay': 'ओवरटाइम भुगतान',
  'OT pay {amount}': 'OT भुगतान {amount}',
  '{h} h double time': '{h} घंटे दोगुनी दर पर',
  'Overtime rate (×)': 'ओवरटाइम दर (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'दिन में {h} घंटे से ऊपर के घंटे ओवरटाइम हैं। घंटे की दर दिहाड़ी को {h} से भाग देकर निकलती है।',
  'Overtime hours are paid at the hourly rate times {rate}.': 'ओवरटाइम के घंटों का भुगतान घंटे की दर का {rate} गुना होता है।',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'ओवरटाइम के घंटों का भुगतान घंटे की दर को इस संख्या से गुणा करके होता है। सामान्य: {rate}।',
  'Enter a number from 1 to 5': '1 से 5 तक की संख्या डालें',
  'California': 'कैलिफ़ोर्निया',
  'Another state': 'कोई दूसरा राज्य',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'कैलिफ़ोर्निया में दिन में 8 घंटे से ऊपर 1.5× और 12 से ऊपर 2× मिलता है। हफ़्ते में लगातार 7वें दिन पहले 8 घंटे 1.5× और उसके बाद 2×। दूसरे राज्यों में हफ़्ते में 40 घंटे से ऊपर 1.5×।',
};

const Map<String, String> overtimeTe = {
  'Overtime pay': 'ఓవర్‌టైమ్ చెల్లింపు',
  'OT pay {amount}': 'OT చెల్లింపు {amount}',
  '{h} h double time': '{h} గం. రెట్టింపు రేటుతో',
  'Overtime rate (×)': 'ఓవర్‌టైమ్ రేటు (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'రోజుకు {h} గంటలకు మించిన గంటలు ఓవర్‌టైమ్. గంట రేటు అంటే రోజు కూలీని {h}తో భాగించగా వచ్చేది.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'ఓవర్‌టైమ్ గంటలకు గంట రేటుకు {rate} రెట్లు చెల్లిస్తారు.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'ఓవర్‌టైమ్ గంటలకు గంట రేటును ఈ సంఖ్యతో గుణించి చెల్లిస్తారు. సాధారణం: {rate}.',
  'Enter a number from 1 to 5': '1 నుండి 5 వరకు ఒక సంఖ్య ఇవ్వండి',
  'California': 'కాలిఫోర్నియా',
  'Another state': 'మరో రాష్ట్రం',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'కాలిఫోర్నియాలో రోజుకు 8 గంటలు దాటితే 1.5×, 12 దాటితే 2×. వారంలో వరుసగా 7వ రోజు మొదటి 8 గంటలకు 1.5×, ఆ తర్వాత 2×. ఇతర రాష్ట్రాల్లో వారానికి 40 గంటలు దాటితే 1.5×.',
};

const Map<String, String> overtimeTa = {
  'Overtime pay': 'கூடுதல் நேர ஊதியம்',
  'OT pay {amount}': 'OT ஊதியம் {amount}',
  '{h} h double time': '{h} மணி இரட்டிப்பு விகிதத்தில்',
  'Overtime rate (×)': 'கூடுதல் நேர விகிதம் (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'ஒரு நாளில் {h} மணிக்கு மேல் உள்ள நேரம் கூடுதல் நேரம். மணி விகிதம் என்பது நாள் கூலியை {h}-ஆல் வகுத்தது.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'கூடுதல் நேரத்துக்கு மணி விகிதத்தின் {rate} மடங்கு வழங்கப்படும்.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'கூடுதல் நேரத்துக்கு மணி விகிதத்தை இந்த எண்ணால் பெருக்கி வழங்கப்படும். இயல்பு: {rate}.',
  'Enter a number from 1 to 5': '1 முதல் 5 வரை ஒரு எண்ணை உள்ளிடவும்',
  'California': 'கலிபோர்னியா',
  'Another state': 'வேறு மாநிலம்',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'கலிபோர்னியாவில் ஒரு நாளில் 8 மணிக்கு மேல் 1.5×, 12-க்கு மேல் 2×. வாரத்தில் தொடர்ந்து 7-வது நாள் முதல் 8 மணிக்கு 1.5×, அதன் பின் 2×. மற்ற மாநிலங்களில் வாரத்துக்கு 40 மணிக்கு மேல் 1.5×.',
};

const Map<String, String> overtimeKn = {
  'Overtime pay': 'ಓವರ್‌ಟೈಮ್ ಪಾವತಿ',
  'OT pay {amount}': 'OT ಪಾವತಿ {amount}',
  '{h} h double time': '{h} ಗಂ. ದುಪ್ಪಟ್ಟು ದರದಲ್ಲಿ',
  'Overtime rate (×)': 'ಓವರ್‌ಟೈಮ್ ದರ (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'ದಿನಕ್ಕೆ {h} ಗಂಟೆ ಮೀರಿದ ಗಂಟೆಗಳು ಓವರ್‌ಟೈಮ್. ಗಂಟೆ ದರ ಎಂದರೆ ದಿನದ ಕೂಲಿಯನ್ನು {h}ರಿಂದ ಭಾಗಿಸಿದ್ದು.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'ಓವರ್‌ಟೈಮ್ ಗಂಟೆಗಳಿಗೆ ಗಂಟೆ ದರದ {rate} ಪಟ್ಟು ಪಾವತಿಸಲಾಗುತ್ತದೆ.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'ಓವರ್‌ಟೈಮ್ ಗಂಟೆಗಳಿಗೆ ಗಂಟೆ ದರವನ್ನು ಈ ಸಂಖ್ಯೆಯಿಂದ ಗುಣಿಸಿ ಪಾವತಿಸಲಾಗುತ್ತದೆ. ಸಾಮಾನ್ಯ: {rate}.',
  'Enter a number from 1 to 5': '1 ರಿಂದ 5 ರವರೆಗಿನ ಸಂಖ್ಯೆ ನಮೂದಿಸಿ',
  'California': 'ಕ್ಯಾಲಿಫೋರ್ನಿಯಾ',
  'Another state': 'ಬೇರೆ ರಾಜ್ಯ',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'ಕ್ಯಾಲಿಫೋರ್ನಿಯಾದಲ್ಲಿ ದಿನಕ್ಕೆ 8 ಗಂಟೆ ಮೀರಿದರೆ 1.5×, 12 ಮೀರಿದರೆ 2×. ವಾರದಲ್ಲಿ ಸತತ 7ನೇ ದಿನ ಮೊದಲ 8 ಗಂಟೆಗೆ 1.5×, ನಂತರ 2×. ಇತರ ರಾಜ್ಯಗಳಲ್ಲಿ ವಾರಕ್ಕೆ 40 ಗಂಟೆ ಮೀರಿದರೆ 1.5×.',
};

const Map<String, String> overtimeMr = {
  'Overtime pay': 'ओव्हरटाइम पगार',
  'OT pay {amount}': 'OT पगार {amount}',
  '{h} h double time': '{h} तास दुप्पट दराने',
  'Overtime rate (×)': 'ओव्हरटाइम दर (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'दिवसात {h} तासांपेक्षा जास्त तास ओव्हरटाइम आहेत. तासाचा दर म्हणजे रोजंदारीला {h} ने भागून येणारा दर.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'ओव्हरटाइमच्या तासांना तासाच्या दराच्या {rate} पट पगार मिळतो.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'ओव्हरटाइमच्या तासांना तासाचा दर या संख्येने गुणून पगार मिळतो. नेहमीचा: {rate}.',
  'Enter a number from 1 to 5': '1 ते 5 मधील संख्या टाका',
  'California': 'कॅलिफोर्निया',
  'Another state': 'दुसरे राज्य',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'कॅलिफोर्नियात दिवसात 8 तासांनंतर 1.5× आणि 12 नंतर 2×. आठवड्यात सलग 7व्या दिवशी पहिल्या 8 तासांना 1.5× आणि नंतर 2×. इतर राज्यांत आठवड्यात 40 तासांनंतर 1.5×.',
};

const Map<String, String> overtimeEs = {
  'Overtime pay': 'Pago de horas extra',
  'OT pay {amount}': 'Pago extra {amount}',
  '{h} h double time': '{h} h a tarifa doble',
  'Overtime rate (×)': 'Tarifa de horas extra (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'Las horas después de {h} en un día son horas extra. La tarifa por hora es el jornal dividido entre {h}.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'Las horas extra se pagan a la tarifa por hora por {rate}.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'Las horas extra se pagan a la tarifa por hora multiplicada por este número. Predeterminado: {rate}.',
  'Enter a number from 1 to 5': 'Escriba un número del 1 al 5',
  'California': 'California',
  'Another state': 'Otro estado',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'California paga 1.5× después de 8 horas en un día y 2× después de 12. El 7.º día seguido de trabajo en una semana paga 1.5× las primeras 8 horas y 2× después. Otros estados pagan 1.5× después de 40 horas a la semana.',
};

const Map<String, String> overtimeMs = {
  'Overtime pay': 'Bayaran kerja lebih masa',
  'OT pay {amount}': 'Bayaran OT {amount}',
  '{h} h double time': '{h} j pada kadar dua kali',
  'Overtime rate (×)': 'Kadar kerja lebih masa (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'Jam selepas {h} jam sehari ialah kerja lebih masa. Kadar sejam ialah gaji harian dibahagi {h}.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'Jam kerja lebih masa dibayar pada kadar sejam darab {rate}.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'Jam kerja lebih masa dibayar pada kadar sejam didarab dengan nombor ini. Lalai: {rate}.',
  'Enter a number from 1 to 5': 'Masukkan nombor dari 1 hingga 5',
  'California': 'California',
  'Another state': 'Negeri lain',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'California membayar 1.5× selepas 8 jam sehari dan 2× selepas 12. Hari ke-7 bekerja berturut-turut dalam seminggu dibayar 1.5× bagi 8 jam pertama dan 2× selepas itu. Negeri lain membayar 1.5× selepas 40 jam seminggu.',
};

const Map<String, String> overtimeZh = {
  'Overtime pay': '加班费',
  'OT pay {amount}': '加班费 {amount}',
  '{h} h double time': '{h} 小时双倍工资',
  'Overtime rate (×)': '加班倍率 (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      '每天超过 {h} 小时的部分为加班。时薪为日薪除以 {h}。',
  'Overtime hours are paid at the hourly rate times {rate}.': '加班时数按时薪的 {rate} 倍支付。',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.': '加班时数按时薪乘以此倍数支付。默认：{rate}。',
  'Enter a number from 1 to 5': '请输入 1 到 5 之间的数字',
  'California': '加利福尼亚州',
  'Another state': '其他州',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      '加州每天超过 8 小时付 1.5 倍，超过 12 小时付 2 倍。一周内连续工作的第 7 天，前 8 小时付 1.5 倍，之后付 2 倍。其他州每周超过 40 小时付 1.5 倍。',
};

const Map<String, String> overtimeAr = {
  'Overtime pay': 'أجر العمل الإضافي',
  'OT pay {amount}': 'أجر إضافي {amount}',
  '{h} h double time': '{h} ساعة بضعف الأجر',
  'Overtime rate (×)': 'معدل العمل الإضافي (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'الساعات بعد {h} في اليوم عمل إضافي. أجر الساعة هو الأجر اليومي مقسومًا على {h}.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'تُدفع ساعات العمل الإضافي بأجر الساعة مضروبًا في {rate}.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'تُدفع ساعات العمل الإضافي بأجر الساعة مضروبًا في هذا الرقم. الافتراضي: {rate}.',
  'Enter a number from 1 to 5': 'أدخل رقمًا من 1 إلى 5',
  'California': 'كاليفورنيا',
  'Another state': 'ولاية أخرى',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'تدفع كاليفورنيا 1.5× بعد 8 ساعات في اليوم و2× بعد 12. واليوم السابع من العمل المتواصل في الأسبوع يُدفع 1.5× لأول 8 ساعات و2× بعدها. وتدفع الولايات الأخرى 1.5× بعد 40 ساعة في الأسبوع.',
};

const Map<String, String> overtimeUr = {
  'Overtime pay': 'اوور ٹائم کی ادائیگی',
  'OT pay {amount}': 'OT ادائیگی {amount}',
  '{h} h double time': '{h} گھنٹے دگنی شرح پر',
  'Overtime rate (×)': 'اوور ٹائم کی شرح (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'دن میں {h} گھنٹوں سے زیادہ کے گھنٹے اوور ٹائم ہیں۔ فی گھنٹہ شرح دن کی اجرت کو {h} سے تقسیم کر کے نکلتی ہے۔',
  'Overtime hours are paid at the hourly rate times {rate}.': 'اوور ٹائم کے گھنٹوں کی ادائیگی فی گھنٹہ شرح کے {rate} گنا ہوتی ہے۔',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'اوور ٹائم کے گھنٹوں کی ادائیگی فی گھنٹہ شرح کو اس عدد سے ضرب دے کر ہوتی ہے۔ طے شدہ: {rate}۔',
  'Enter a number from 1 to 5': '1 سے 5 تک کوئی عدد درج کریں',
  'California': 'کیلیفورنیا',
  'Another state': 'کوئی اور ریاست',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'کیلیفورنیا میں دن میں 8 گھنٹوں کے بعد 1.5× اور 12 کے بعد 2× ملتا ہے۔ ہفتے میں لگاتار ساتویں دن پہلے 8 گھنٹے 1.5× اور اس کے بعد 2×۔ دوسری ریاستوں میں ہفتے میں 40 گھنٹوں کے بعد 1.5×۔',
};

const Map<String, String> overtimeMl = {
  'Overtime pay': 'ഓവർടൈം വേതനം',
  'OT pay {amount}': 'OT വേതനം {amount}',
  '{h} h double time': '{h} മണിക്കൂർ ഇരട്ടി നിരക്കിൽ',
  'Overtime rate (×)': 'ഓവർടൈം നിരക്ക് (×)',
  'Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.':
      'ഒരു ദിവസം {h} മണിക്കൂറിന് ശേഷമുള്ള സമയം ഓവർടൈമാണ്. മണിക്കൂർ നിരക്ക് ദിവസക്കൂലിയെ {h} കൊണ്ട് ഹരിച്ചതാണ്.',
  'Overtime hours are paid at the hourly rate times {rate}.': 'ഓവർടൈം മണിക്കൂറുകൾക്ക് മണിക്കൂർ നിരക്കിന്റെ {rate} മടങ്ങ് നൽകും.',
  'Overtime hours are paid at the hourly rate times this number. Default: {rate}.':
      'ഓവർടൈം മണിക്കൂറുകൾക്ക് മണിക്കൂർ നിരക്കിനെ ഈ സംഖ്യ കൊണ്ട് ഗുണിച്ച് നൽകും. സാധാരണ: {rate}.',
  'Enter a number from 1 to 5': '1 മുതൽ 5 വരെയുള്ള ഒരു സംഖ്യ നൽകുക',
  'California': 'കാലിഫോർണിയ',
  'Another state': 'മറ്റൊരു സംസ്ഥാനം',
  'California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.':
      'കാലിഫോർണിയയിൽ ഒരു ദിവസം 8 മണിക്കൂറിന് ശേഷം 1.5×, 12-ന് ശേഷം 2×. ആഴ്ചയിൽ തുടർച്ചയായ 7-ാം ദിവസം ആദ്യ 8 മണിക്കൂറിന് 1.5×, പിന്നീട് 2×. മറ്റ് സംസ്ഥാനങ്ങളിൽ ആഴ്ചയിൽ 40 മണിക്കൂറിന് ശേഷം 1.5×.',
};
