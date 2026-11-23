/// Labels from the November 2026 India compliance pass (yearly rules
/// reminder, 18+ checks, client address on GST bills). Machine-drafted:
/// a native speaker should read them, like the privacy notice. Spread into
/// each Indian language's table.
library;

const Map<String, String> complianceHi = {
  'Every worker in this list is 18 or older': 'इस सूची का हर मज़दूर 18 साल या उससे ज़्यादा उम्र का है',
  'This worker is 18 or older': 'यह मज़दूर 18 साल या उससे ज़्यादा उम्र का है',
  'The law does not allow anyone under 18 to work on a building site.':
      'क़ानून 18 साल से कम उम्र के किसी को भी निर्माण साइट पर काम करने की इजाज़त नहीं देता।',
  'FieldOS is for people aged 18 and over.': 'FieldOS 18 साल और उससे ज़्यादा उम्र के लोगों के लिए है।',
  'Our yearly reminder of the rules': 'नियमों की हमारी सालाना याद',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'कृपया उपयोग की शर्तें और गोपनीयता नीति फिर से पढ़ें। ऐसा कुछ भी साझा न करें जो लोगों को गाली दे या धमकाए, क़ानून तोड़े या किसी की निजी जानकारी बताए। ऐसा करने पर हम उसे हटा सकते हैं और खाता रोक या बंद कर सकते हैं।',
  'Got it': 'ठीक है',
  'Client address': 'क्लाइंट का पता',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'क्लाइंट का पता डालें। GST-पंजीकृत क्लाइंट के लिए, या 50,000 या उससे ज़्यादा की राशि पर, टैक्स इनवॉइस में पता होना ज़रूरी है।',
};

const Map<String, String> complianceTe = {
  'Every worker in this list is 18 or older': 'ఈ జాబితాలోని ప్రతి కార్మికుడి వయసు 18 లేదా అంతకంటే ఎక్కువ',
  'This worker is 18 or older': 'ఈ కార్మికుడి వయసు 18 లేదా అంతకంటే ఎక్కువ',
  'The law does not allow anyone under 18 to work on a building site.':
      '18 ఏళ్ల లోపు ఎవరూ నిర్మాణ స్థలంలో పని చేయడానికి చట్టం అనుమతించదు.',
  'FieldOS is for people aged 18 and over.': 'FieldOS 18 ఏళ్లు మరియు అంతకంటే ఎక్కువ వయసు వారి కోసం.',
  'Our yearly reminder of the rules': 'నియమాల గురించి మా ఏటా గుర్తు',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'దయచేసి ఉపయోగ నిబంధనలు, గోప్యతా విధానం మళ్ళీ చదవండి. ఎవరినైనా దూషించే లేదా బెదిరించే, చట్టాన్ని ఉల్లంఘించే లేదా ఎవరి వ్యక్తిగత వివరాలనైనా బయటపెట్టే దేన్నీ పంచుకోవద్దు. అలా చేస్తే మేము దాన్ని తీసివేసి, ఖాతాను నిలిపివేయవచ్చు లేదా మూసివేయవచ్చు.',
  'Got it': 'సరే',
  'Client address': 'క్లయింట్ చిరునామా',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'క్లయింట్ చిరునామా చేర్చండి. GST నమోదైన క్లయింట్‌కు, లేదా విలువ 50,000 లేదా అంతకంటే ఎక్కువ ఉన్నప్పుడు, టాక్స్ ఇన్వాయిస్‌లో అది ఉండాలి.',
};

const Map<String, String> complianceTa = {
  'Every worker in this list is 18 or older':
      'இந்தப் பட்டியலில் உள்ள ஒவ்வொரு தொழிலாளருக்கும் 18 வயது அல்லது அதற்கு மேல்',
  'This worker is 18 or older': 'இந்தத் தொழிலாளருக்கு 18 வயது அல்லது அதற்கு மேல்',
  'The law does not allow anyone under 18 to work on a building site.':
      '18 வயதுக்குட்பட்ட யாரும் கட்டுமானத் தளத்தில் வேலை செய்ய சட்டம் அனுமதிப்பதில்லை.',
  'FieldOS is for people aged 18 and over.': 'FieldOS 18 வயது மற்றும் அதற்கு மேற்பட்டவர்களுக்கானது.',
  'Our yearly reminder of the rules': 'விதிகள் பற்றிய எங்கள் ஆண்டு நினைவூட்டல்',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'பயன்பாட்டு விதிமுறைகளையும் தனியுரிமைக் கொள்கையையும் மீண்டும் படியுங்கள். யாரையும் திட்டும் அல்லது மிரட்டும், சட்டத்தை மீறும் அல்லது ஒருவரின் தனிப்பட்ட விவரங்களை வெளியிடும் எதையும் பகிர வேண்டாம். அப்படிச் செய்தால் அதை நீக்கி, கணக்கை நிறுத்தவோ மூடவோ செய்யலாம்.',
  'Got it': 'சரி',
  'Client address': 'வாடிக்கையாளர் முகவரி',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'வாடிக்கையாளர் முகவரியைச் சேர்க்கவும். GST பதிவு பெற்ற வாடிக்கையாளருக்கு, அல்லது மதிப்பு 50,000 அல்லது அதற்கு மேல் இருந்தால், வரி விலைப்பட்டியலில் அது இருக்க வேண்டும்.',
};

const Map<String, String> complianceKn = {
  'Every worker in this list is 18 or older': 'ಈ ಪಟ್ಟಿಯ ಪ್ರತಿ ಕಾರ್ಮಿಕರ ವಯಸ್ಸು 18 ಅಥವಾ ಹೆಚ್ಚು',
  'This worker is 18 or older': 'ಈ ಕಾರ್ಮಿಕರ ವಯಸ್ಸು 18 ಅಥವಾ ಹೆಚ್ಚು',
  'The law does not allow anyone under 18 to work on a building site.':
      '18 ವರ್ಷದೊಳಗಿನ ಯಾರೂ ಕಟ್ಟಡ ಸ್ಥಳದಲ್ಲಿ ಕೆಲಸ ಮಾಡಲು ಕಾನೂನು ಅನುಮತಿಸುವುದಿಲ್ಲ.',
  'FieldOS is for people aged 18 and over.': 'FieldOS 18 ವರ್ಷ ಮತ್ತು ಮೇಲ್ಪಟ್ಟವರಿಗಾಗಿ.',
  'Our yearly reminder of the rules': 'ನಿಯಮಗಳ ಬಗ್ಗೆ ನಮ್ಮ ವಾರ್ಷಿಕ ನೆನಪು',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'ದಯವಿಟ್ಟು ಬಳಕೆಯ ನಿಯಮಗಳು ಮತ್ತು ಗೌಪ್ಯತಾ ನೀತಿಯನ್ನು ಮತ್ತೆ ಓದಿ. ಜನರನ್ನು ನಿಂದಿಸುವ ಅಥವಾ ಬೆದರಿಸುವ, ಕಾನೂನು ಮುರಿಯುವ ಅಥವಾ ಯಾರದೇ ಖಾಸಗಿ ವಿವರಗಳನ್ನು ಬಹಿರಂಗಪಡಿಸುವ ಯಾವುದನ್ನೂ ಹಂಚಿಕೊಳ್ಳಬೇಡಿ. ಹಾಗೆ ಮಾಡಿದರೆ ನಾವು ಅದನ್ನು ತೆಗೆದುಹಾಕಿ ಖಾತೆಯನ್ನು ತಡೆಹಿಡಿಯಬಹುದು ಅಥವಾ ಮುಚ್ಚಬಹುದು.',
  'Got it': 'ಸರಿ',
  'Client address': 'ಗ್ರಾಹಕರ ವಿಳಾಸ',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'ಗ್ರಾಹಕರ ವಿಳಾಸ ಸೇರಿಸಿ. GST ನೋಂದಾಯಿತ ಗ್ರಾಹಕರಿಗೆ, ಅಥವಾ ಮೊತ್ತ 50,000 ಅಥವಾ ಹೆಚ್ಚಿದ್ದಾಗ, ತೆರಿಗೆ ಇನ್‌ವಾಯ್ಸ್‌ನಲ್ಲಿ ಅದು ಇರಬೇಕು.',
};

const Map<String, String> complianceMr = {
  'Every worker in this list is 18 or older': 'या यादीतील प्रत्येक कामगाराचे वय 18 किंवा त्याहून जास्त आहे',
  'This worker is 18 or older': 'या कामगाराचे वय 18 किंवा त्याहून जास्त आहे',
  'The law does not allow anyone under 18 to work on a building site.':
      'कायदा 18 वर्षांखालील कोणालाही बांधकाम साइटवर काम करू देत नाही.',
  'FieldOS is for people aged 18 and over.': 'FieldOS 18 वर्षे आणि त्याहून जास्त वयाच्या लोकांसाठी आहे.',
  'Our yearly reminder of the rules': 'नियमांची आमची वार्षिक आठवण',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'कृपया वापराच्या अटी आणि गोपनीयता धोरण पुन्हा वाचा. लोकांना शिवीगाळ करणारे किंवा धमकावणारे, कायदा मोडणारे किंवा कोणाची खासगी माहिती उघड करणारे काहीही शेअर करू नका. असे केल्यास आम्ही ते काढून टाकू शकतो आणि खाते थांबवू किंवा बंद करू शकतो.',
  'Got it': 'ठीक आहे',
  'Client address': 'ग्राहकाचा पत्ता',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'ग्राहकाचा पत्ता टाका. GST-नोंदणीकृत ग्राहकासाठी, किंवा रक्कम 50,000 किंवा त्याहून जास्त असल्यास, टॅक्स इनव्हॉइसवर तो असणे आवश्यक आहे.',
};

// The other markets' languages (the US, Malaysia, UAE and UK apps).

const Map<String, String> complianceEs = {
  'Every worker in this list is 18 or older':
      'Todos los trabajadores de esta lista tienen 18 años o más',
  'This worker is 18 or older':
      'Este trabajador tiene 18 años o más',
  'The law does not allow anyone under 18 to work on a building site.':
      'La ley no permite que nadie menor de 18 años trabaje en una obra.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS es para personas de 18 años o más.',
  'Our yearly reminder of the rules':
      'Nuestro recordatorio anual de las reglas',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'Vuelva a leer los términos de uso y la política de privacidad. No comparta nada que insulte o amenace a otras personas, infrinja la ley o revele datos privados de alguien. Si lo hace, podemos eliminarlo y suspender o cerrar la cuenta.',
  'Got it':
      'Entendido',
  'Client address':
      'Dirección del cliente',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'Añada la dirección del cliente. Una factura con impuestos debe mostrarla para un cliente registrado, o cuando el valor es de 50,000 o más.',
};

const Map<String, String> complianceMs = {
  'Every worker in this list is 18 or older':
      'Setiap pekerja dalam senarai ini berumur 18 tahun ke atas',
  'This worker is 18 or older':
      'Pekerja ini berumur 18 tahun ke atas',
  'The law does not allow anyone under 18 to work on a building site.':
      'Undang-undang tidak membenarkan sesiapa di bawah 18 tahun bekerja di tapak bina.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS adalah untuk orang berumur 18 tahun ke atas.',
  'Our yearly reminder of the rules':
      'Peringatan tahunan kami tentang peraturan',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'Sila baca semula terma penggunaan dan dasar privasi. Jangan kongsi apa-apa yang menghina atau mengugut orang, melanggar undang-undang atau mendedahkan butiran peribadi seseorang. Jika anda berbuat demikian, kami boleh membuangnya dan menggantung atau menutup akaun.',
  'Got it':
      'Faham',
  'Client address':
      'Alamat pelanggan',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'Tambah alamat pelanggan. Invois cukai mesti menunjukkannya untuk pelanggan berdaftar, atau apabila nilainya 50,000 atau lebih.',
};

const Map<String, String> complianceZh = {
  'Every worker in this list is 18 or older':
      '此名单中的每位工人都已年满18岁',
  'This worker is 18 or older':
      '这位工人已年满18岁',
  'The law does not allow anyone under 18 to work on a building site.':
      '法律不允许未满18岁的人在建筑工地工作。',
  'FieldOS is for people aged 18 and over.':
      'FieldOS 适用于年满18岁的人。',
  'Our yearly reminder of the rules':
      '每年一次的规则提醒',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      '请再次阅读使用条款和隐私政策。不要分享任何辱骂或威胁他人、违法或泄露他人隐私信息的内容。如有此类行为，我们可能会删除该内容，并暂停或关闭账户。',
  'Got it':
      '知道了',
  'Client address':
      '客户地址',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      '请填写客户地址。开给已登记客户的税务发票，或金额达到50,000或以上时，必须显示地址。',
};

const Map<String, String> complianceAr = {
  'Every worker in this list is 18 or older':
      'كل عامل في هذه القائمة عمره 18 عامًا أو أكثر',
  'This worker is 18 or older':
      'عمر هذا العامل 18 عامًا أو أكثر',
  'The law does not allow anyone under 18 to work on a building site.':
      'لا يسمح القانون لأي شخص دون 18 عامًا بالعمل في موقع البناء.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS مخصص للأشخاص بعمر 18 عامًا فأكثر.',
  'Our yearly reminder of the rules':
      'تذكيرنا السنوي بالقواعد',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'يُرجى قراءة شروط الاستخدام وسياسة الخصوصية مرة أخرى. لا تشارك أي شيء يسيء إلى الناس أو يهددهم أو يخالف القانون أو يكشف البيانات الخاصة لأي شخص. إذا فعلت ذلك، فقد نحذفه ونوقف الحساب أو نغلقه.',
  'Got it':
      'فهمت',
  'Client address':
      'عنوان العميل',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'أضف عنوان العميل. يجب أن تُظهره الفاتورة الضريبية لعميل مسجل، أو عندما تكون القيمة 50,000 أو أكثر.',
};

const Map<String, String> complianceUr = {
  'Every worker in this list is 18 or older':
      'اس فہرست کا ہر مزدور 18 سال یا اس سے زیادہ عمر کا ہے',
  'This worker is 18 or older':
      'یہ مزدور 18 سال یا اس سے زیادہ عمر کا ہے',
  'The law does not allow anyone under 18 to work on a building site.':
      'قانون 18 سال سے کم عمر کسی کو بھی تعمیراتی سائٹ پر کام کی اجازت نہیں دیتا۔',
  'FieldOS is for people aged 18 and over.':
      'FieldOS اٹھارہ سال اور اس سے زیادہ عمر کے لوگوں کے لیے ہے۔',
  'Our yearly reminder of the rules':
      'قواعد کی ہماری سالانہ یاد دہانی',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'براہ کرم استعمال کی شرائط اور رازداری کی پالیسی دوبارہ پڑھیں۔ کوئی ایسی چیز شیئر نہ کریں جو لوگوں کو گالی دے یا دھمکائے، قانون توڑے یا کسی کی نجی معلومات ظاہر کرے۔ ایسا کرنے پر ہم اسے ہٹا سکتے ہیں اور اکاؤنٹ معطل یا بند کر سکتے ہیں۔',
  'Got it':
      'ٹھیک ہے',
  'Client address':
      'کلائنٹ کا پتہ',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'کلائنٹ کا پتہ درج کریں۔ رجسٹرڈ کلائنٹ کے لیے، یا جب رقم 50,000 یا اس سے زیادہ ہو، ٹیکس انوائس پر پتہ ہونا ضروری ہے۔',
};

const Map<String, String> complianceMl = {
  'Every worker in this list is 18 or older':
      'ഈ പട്ടികയിലെ എല്ലാ തൊഴിലാളികൾക്കും 18 വയസ്സോ അതിൽ കൂടുതലോ ഉണ്ട്',
  'This worker is 18 or older':
      'ഈ തൊഴിലാളിക്ക് 18 വയസ്സോ അതിൽ കൂടുതലോ ഉണ്ട്',
  'The law does not allow anyone under 18 to work on a building site.':
      '18 വയസ്സിൽ താഴെയുള്ള ആരെയും നിർമ്മാണ സ്ഥലത്ത് ജോലി ചെയ്യാൻ നിയമം അനുവദിക്കുന്നില്ല.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS 18 വയസ്സും അതിൽ കൂടുതലും ഉള്ളവർക്കുള്ളതാണ്.',
  'Our yearly reminder of the rules':
      'നിയമങ്ങളെക്കുറിച്ചുള്ള ഞങ്ങളുടെ വാർഷിക ഓർമ്മപ്പെടുത്തൽ',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'ഉപയോഗ നിബന്ധനകളും സ്വകാര്യതാ നയവും വീണ്ടും വായിക്കുക. ആളുകളെ അധിക്ഷേപിക്കുന്നതോ ഭീഷണിപ്പെടുത്തുന്നതോ നിയമം ലംഘിക്കുന്നതോ ആരുടെയെങ്കിലും സ്വകാര്യ വിവരങ്ങൾ വെളിപ്പെടുത്തുന്നതോ ആയ ഒന്നും പങ്കിടരുത്. അങ്ങനെ ചെയ്താൽ ഞങ്ങൾ അത് നീക്കം ചെയ്യുകയും അക്കൗണ്ട് താൽക്കാലികമായി നിർത്തുകയോ അടയ്ക്കുകയോ ചെയ്തേക്കാം.',
  'Got it':
      'ശരി',
  'Client address':
      'ക്ലയന്റിന്റെ വിലാസം',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'ക്ലയന്റിന്റെ വിലാസം ചേർക്കുക. രജിസ്റ്റർ ചെയ്ത ക്ലയന്റിന്, അല്ലെങ്കിൽ തുക 50,000 അല്ലെങ്കിൽ അതിൽ കൂടുതലാണെങ്കിൽ, ടാക്സ് ഇൻവോയ്സിൽ അത് കാണിക്കണം.',
};

const Map<String, String> compliancePl = {
  'Every worker in this list is 18 or older':
      'Każdy pracownik z tej listy ma co najmniej 18 lat',
  'This worker is 18 or older':
      'Ten pracownik ma co najmniej 18 lat',
  'The law does not allow anyone under 18 to work on a building site.':
      'Prawo nie pozwala, by osoba poniżej 18 lat pracowała na budowie.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS jest dla osób w wieku 18 lat i starszych.',
  'Our yearly reminder of the rules':
      'Nasze coroczne przypomnienie zasad',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'Przeczytaj ponownie warunki korzystania i politykę prywatności. Nie udostępniaj niczego, co obraża lub zastrasza ludzi, łamie prawo lub ujawnia czyjeś prywatne dane. Jeśli to zrobisz, możemy to usunąć oraz zawiesić lub zamknąć konto.',
  'Got it':
      'Rozumiem',
  'Client address':
      'Adres klienta',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'Dodaj adres klienta. Faktura podatkowa musi go zawierać dla zarejestrowanego klienta lub gdy wartość wynosi 50,000 lub więcej.',
};

const Map<String, String> complianceRo = {
  'Every worker in this list is 18 or older':
      'Fiecare muncitor din această listă are cel puțin 18 ani',
  'This worker is 18 or older':
      'Acest muncitor are cel puțin 18 ani',
  'The law does not allow anyone under 18 to work on a building site.':
      'Legea nu permite nimănui sub 18 ani să lucreze pe un șantier.',
  'FieldOS is for people aged 18 and over.':
      'FieldOS este pentru persoane de 18 ani și peste.',
  'Our yearly reminder of the rules':
      'Memento-ul nostru anual despre reguli',
  'Please read the terms of use and privacy policy again. Do not share anything that abuses or threatens people, breaks the law or gives out someone\'s private details. If you do, we may remove it and suspend or close the account.':
      'Citiți din nou termenii de utilizare și politica de confidențialitate. Nu distribuiți nimic care jignește sau amenință oamenii, încalcă legea sau dezvăluie datele private ale cuiva. Dacă o faceți, putem elimina conținutul și suspenda sau închide contul.',
  'Got it':
      'Am înțeles',
  'Client address':
      'Adresa clientului',
  'Add the client\'s address. A tax invoice must show it for a GST-registered client, or when the value is 50,000 or more.':
      'Adăugați adresa clientului. O factură fiscală trebuie să o arate pentru un client înregistrat sau când valoarea este de 50,000 sau mai mult.',
};
