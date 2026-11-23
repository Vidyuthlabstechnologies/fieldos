"""Writes lib/l10n/strings_consent_<lang>.dart: the check-in notice and its
switch in Your privacy. Machine-drafted translations: have native speakers
read them. Run from fieldos_mobile/:  python3 tool/l10n_src/gen_consent.py
"""
import os

LANGS = ['hi', 'te', 'ta', 'kn', 'mr', 'es', 'ms', 'zh', 'ar', 'ur', 'ml']
K1 = 'Before your first check-in'
K2 = ('When you check in or out, FieldOS reads your location once and takes a photo with the front camera, so your '
      'company can see you were at the site. Only the owner and project managers see them. The photo is deleted '
      'as soon as your day is verified; the location and the result stay with your attendance record. Your location is never tracked in the background, and the photo is never used for '
      'face recognition.')
K3 = 'If you do not agree, ask your supervisor to mark your attendance instead.'
K4 = 'Photo and location for my attendance'
K5 = 'Read once at each check-in and check-out, never in the background'
T = {
 K1: ['पहली बार चेक इन से पहले', 'మొదటి చెక్ ఇన్‌కు ముందు', 'முதல் செக் இன் செய்யும் முன்', 'ಮೊದಲ ಚೆಕ್ ಇನ್‌ಗೆ ಮುನ್ನ', 'पहिल्या चेक इनपूर्वी',
      'Antes de tu primera entrada', 'Sebelum daftar masuk pertama anda', '首次签到之前', 'قبل أول تسجيل حضور', 'پہلی حاضری سے پہلے', 'ആദ്യ ചെക്ക് ഇന്നിന് മുമ്പ്'],
 K2: ['चेक इन या आउट करते समय FieldOS एक बार आपका लोकेशन पढ़ता है और सामने के कैमरे से फ़ोटो लेता है, ताकि आपकी कंपनी देख सके कि आप साइट पर थे। सिर्फ़ मालिक और प्रोजेक्ट मैनेजर उन्हें देखते हैं। आपका दिन सत्यापित होते ही फ़ोटो मिटा दी जाती है; लोकेशन और नतीजा आपकी हाज़िरी के रिकॉर्ड के साथ रहते हैं। आपका लोकेशन कभी पीछे से ट्रैक नहीं होता, और फ़ोटो कभी चेहरा पहचानने के लिए इस्तेमाल नहीं होती।',
      'మీరు చెక్ ఇన్ లేదా అవుట్ చేసినప్పుడు FieldOS మీ లొకేషన్‌ను ఒకసారి చదివి, ముందు కెమెరాతో ఫోటో తీస్తుంది, మీరు సైట్‌లో ఉన్నారని మీ కంపెనీ చూడడానికి. యజమాని, ప్రాజెక్ట్ మేనేజర్లు మాత్రమే వాటిని చూస్తారు. మీ రోజు ధృవీకరించిన వెంటనే ఫోటో తొలగించబడుతుంది; లొకేషన్, ఫలితం మీ హాజరు రికార్డుతో ఉంటాయి. మీ లొకేషన్ ఎప్పుడూ వెనుకనుండి ట్రాక్ కాదు, ఫోటోను ముఖ గుర్తింపుకు ఎప్పుడూ వాడరు.',
      'நீங்கள் செக் இன் அல்லது அவுட் செய்யும்போது FieldOS உங்கள் இருப்பிடத்தை ஒருமுறை படித்து, முன் கேமராவில் ஒரு புகைப்படம் எடுக்கும், நீங்கள் தளத்தில் இருந்ததை உங்கள் நிறுவனம் பார்க்க. உரிமையாளரும் திட்ட மேலாளர்களும் மட்டுமே அவற்றைப் பார்ப்பார்கள். உங்கள் நாள் சரிபார்க்கப்பட்டதும் புகைப்படம் நீக்கப்படும்; இருப்பிடமும் முடிவும் உங்கள் வருகைப் பதிவுடன் இருக்கும். உங்கள் இருப்பிடம் பின்னணியில் ஒருபோதும் கண்காணிக்கப்படாது, புகைப்படம் முக அடையாளத்துக்கு ஒருபோதும் பயன்படுத்தப்படாது.',
      'ನೀವು ಚೆಕ್ ಇನ್ ಅಥವಾ ಔಟ್ ಮಾಡುವಾಗ FieldOS ನಿಮ್ಮ ಸ್ಥಳವನ್ನು ಒಮ್ಮೆ ಓದಿ, ಮುಂದಿನ ಕ್ಯಾಮೆರಾದಿಂದ ಫೋಟೋ ತೆಗೆಯುತ್ತದೆ, ನೀವು ಸೈಟ್‌ನಲ್ಲಿದ್ದೀರಿ ಎಂದು ನಿಮ್ಮ ಕಂಪನಿ ನೋಡಲು. ಮಾಲೀಕರು ಮತ್ತು ಪ್ರಾಜೆಕ್ಟ್ ಮ್ಯಾನೇಜರ್‌ಗಳು ಮಾತ್ರ ಅವನ್ನು ನೋಡುತ್ತಾರೆ. ನಿಮ್ಮ ದಿನ ಪರಿಶೀಲನೆಯಾದ ತಕ್ಷಣ ಫೋಟೋ ಅಳಿಸಲಾಗುತ್ತದೆ; ಸ್ಥಳ ಮತ್ತು ಫಲಿತಾಂಶ ನಿಮ್ಮ ಹಾಜರಾತಿ ದಾಖಲೆಯೊಂದಿಗೆ ಉಳಿಯುತ್ತವೆ. ನಿಮ್ಮ ಸ್ಥಳವನ್ನು ಎಂದಿಗೂ ಹಿನ್ನೆಲೆಯಲ್ಲಿ ಟ್ರ್ಯಾಕ್ ಮಾಡುವುದಿಲ್ಲ, ಫೋಟೋವನ್ನು ಮುಖ ಗುರುತಿಸುವಿಕೆಗೆ ಎಂದಿಗೂ ಬಳಸುವುದಿಲ್ಲ.',
      'तुम्ही चेक इन किंवा आउट करता तेव्हा FieldOS तुमचे लोकेशन एकदा वाचते आणि पुढच्या कॅमेऱ्याने फोटो घेते, म्हणजे तुम्ही साइटवर होता हे तुमच्या कंपनीला दिसेल. फक्त मालक आणि प्रकल्प व्यवस्थापक ते पाहतात. तुमचा दिवस पडताळताच फोटो हटवला जातो; लोकेशन आणि निकाल तुमच्या हजेरीच्या नोंदीसोबत राहतात. तुमचे लोकेशन कधीही मागून ट्रॅक होत नाही, आणि फोटो कधीही चेहरा ओळखण्यासाठी वापरला जात नाही.',
      'Cuando marcas entrada o salida, FieldOS lee tu ubicación una vez y toma una foto con la cámara frontal, para que tu empresa vea que estuviste en la obra. Solo el dueño y los gerentes de proyecto las ven. La foto se borra en cuanto se verifica tu día; la ubicación y el resultado quedan en tu registro de asistencia. Tu ubicación nunca se rastrea en segundo plano y la foto nunca se usa para reconocimiento facial.',
      'Apabila anda daftar masuk atau keluar, FieldOS membaca lokasi anda sekali dan mengambil foto dengan kamera hadapan, supaya syarikat anda dapat melihat anda berada di tapak. Hanya pemilik dan pengurus projek yang melihatnya. Foto dipadam sebaik sahaja hari anda disahkan; lokasi dan keputusannya kekal bersama rekod kehadiran anda. Lokasi anda tidak pernah dijejak di latar belakang, dan foto tidak pernah digunakan untuk pengecaman wajah.',
      '签到或签退时，FieldOS 会读取一次您的位置，并用前置摄像头拍一张照片，让公司看到您在工地。只有老板和项目经理能看到。当天考勤核实后照片会立即删除，位置和核实结果随您的考勤记录保留。您的位置绝不会在后台被跟踪，照片也绝不会用于人脸识别。',
      'عند تسجيل الحضور أو الانصراف، يقرأ FieldOS موقعك مرة واحدة ويلتقط صورة بالكاميرا الأمامية، لكي ترى شركتك أنك كنت في الموقع. لا يراهما إلا المالك ومديرو المشاريع. تُحذف الصورة فور التحقق من يومك، ويبقى الموقع والنتيجة مع سجل حضورك. لا يُتتبَّع موقعك في الخلفية أبداً، ولا تُستخدم الصورة أبداً للتعرّف على الوجه.',
      'حاضری لگاتے یا ختم کرتے وقت FieldOS ایک بار آپ کا مقام پڑھتا ہے اور سامنے والے کیمرے سے تصویر لیتا ہے، تاکہ آپ کی کمپنی دیکھ سکے کہ آپ سائٹ پر تھے۔ صرف مالک اور پروجیکٹ مینیجر انہیں دیکھتے ہیں۔ آپ کا دن تصدیق ہوتے ہی تصویر مٹا دی جاتی ہے؛ مقام اور نتیجہ آپ کی حاضری کے ریکارڈ کے ساتھ رہتے ہیں۔ آپ کا مقام کبھی پس منظر میں ٹریک نہیں ہوتا، اور تصویر کبھی چہرہ پہچاننے کے لیے استعمال نہیں ہوتی۔',
      'നിങ്ങൾ ചെക്ക് ഇൻ അല്ലെങ്കിൽ ഔട്ട് ചെയ്യുമ്പോൾ FieldOS നിങ്ങളുടെ ലൊക്കേഷൻ ഒരിക്കൽ വായിക്കുകയും മുൻ ക്യാമറ കൊണ്ട് ഒരു ഫോട്ടോ എടുക്കുകയും ചെയ്യും, നിങ്ങൾ സൈറ്റിൽ ഉണ്ടായിരുന്നുവെന്ന് കമ്പനിക്ക് കാണാൻ. ഉടമയും പ്രോജക്ട് മാനേജർമാരും മാത്രമേ അവ കാണൂ. നിങ്ങളുടെ ദിവസം പരിശോധിച്ച ഉടൻ ഫോട്ടോ മായ്ക്കും; ലൊക്കേഷനും ഫലവും നിങ്ങളുടെ ഹാജർ രേഖയോടൊപ്പം നിലനിൽക്കും. നിങ്ങളുടെ ലൊക്കേഷൻ ഒരിക്കലും പശ്ചാത്തലത്തിൽ ട്രാക്ക് ചെയ്യില്ല, ഫോട്ടോ മുഖം തിരിച്ചറിയാൻ ഒരിക്കലും ഉപയോഗിക്കില്ല.'],
 K3: ['अगर आप सहमत नहीं हैं, तो अपने सुपरवाइज़र से अपनी हाज़िरी लगवाएँ।', 'మీరు అంగీకరించకపోతే, మీ హాజరు వేయమని మీ సూపర్‌వైజర్‌ను అడగండి.',
      'நீங்கள் ஒப்புக்கொள்ளவில்லை என்றால், உங்கள் வருகையைப் பதிய உங்கள் மேற்பார்வையாளரிடம் கேளுங்கள்.', 'ನೀವು ಒಪ್ಪದಿದ್ದರೆ, ನಿಮ್ಮ ಹಾಜರಿ ಹಾಕಲು ನಿಮ್ಮ ಸೂಪರ್‌ವೈಸರ್‌ಗೆ ಕೇಳಿ.',
      'तुम्ही सहमत नसल्यास, तुमची हजेरी लावायला तुमच्या सुपरवायझरला सांगा.', 'Si no estás de acuerdo, pide a tu supervisor que marque tu asistencia.',
      'Jika anda tidak bersetuju, minta penyelia anda menanda kehadiran anda.', '如果您不同意，请让主管为您记录考勤。', 'إذا لم توافق، فاطلب من مشرفك تسجيل حضورك بدلاً من ذلك.',
      'اگر آپ متفق نہیں ہیں تو اپنے سپروائزر سے اپنی حاضری لگوائیں۔', 'നിങ്ങൾ സമ്മതിക്കുന്നില്ലെങ്കിൽ, ഹാജർ രേഖപ്പെടുത്താൻ സൂപ്പർവൈസറോട് പറയുക.'],
 K4: ['मेरी हाज़िरी के लिए फ़ोटो और लोकेशन', 'నా హాజరు కోసం ఫోటో, లొకేషన్', 'என் வருகைக்கான புகைப்படமும் இருப்பிடமும்', 'ನನ್ನ ಹಾಜರಿಗಾಗಿ ಫೋಟೋ ಮತ್ತು ಸ್ಥಳ',
      'माझ्या हजेरीसाठी फोटो आणि लोकेशन', 'Foto y ubicación para mi asistencia', 'Foto dan lokasi untuk kehadiran saya', '用于我考勤的照片和位置',
      'الصورة والموقع لتسجيل حضوري', 'میری حاضری کے لیے تصویر اور مقام', 'എന്റെ ഹാജറിനുള്ള ഫോട്ടോയും ലൊക്കേഷനും'],
 K5: ['हर चेक इन और चेक आउट पर एक बार, कभी पीछे से नहीं', 'ప్రతి చెక్ ఇన్, చెక్ అవుట్‌కు ఒకసారి, ఎప్పుడూ వెనుకనుండి కాదు',
      'ஒவ்வொரு செக் இன், செக் அவுட்டிலும் ஒருமுறை, பின்னணியில் ஒருபோதும் இல்லை', 'ಪ್ರತಿ ಚೆಕ್ ಇನ್ ಮತ್ತು ಚೆಕ್ ಔಟ್‌ನಲ್ಲಿ ಒಮ್ಮೆ, ಎಂದಿಗೂ ಹಿನ್ನೆಲೆಯಲ್ಲಿ ಅಲ್ಲ',
      'प्रत्येक चेक इन आणि चेक आउटला एकदा, कधीही मागून नाही', 'Se lee una vez en cada entrada y salida, nunca en segundo plano',
      'Dibaca sekali pada setiap daftar masuk dan keluar, tidak pernah di latar belakang', '每次签到和签退时读取一次，绝不在后台读取',
      'تُقرأ مرة عند كل تسجيل حضور وانصراف، ولا تُقرأ في الخلفية أبداً', 'ہر حاضری اور رخصتی پر ایک بار، کبھی پس منظر میں نہیں',
      'ഓരോ ചെക്ക് ഇന്നിലും ഔട്ടിലും ഒരിക്കൽ, ഒരിക്കലും പശ്ചാത്തലത്തിൽ ഇല്ല'],
}

def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

HERE = os.path.dirname(__file__)
for i, lang in enumerate(LANGS):
    out = ['// The check-in notice and its switch in Your privacy.',
           '// Generated by tool/l10n_src/gen_consent.py.',
           '// ignore_for_file: lines_longer_than_80_chars', '',
           'const Map<String, String> consent%s = {' % lang.capitalize()]
    for k in sorted(T):
        assert len(T[k]) == len(LANGS), k
        out.append('  %s: %s,' % (q(k), q(T[k][i])))
    out.append('};')
    with open(os.path.join(HERE, '..', '..', 'lib', 'l10n', 'strings_consent_%s.dart' % lang), 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
