/// First run: Google sign-in first, the "Get your first site running"
/// checklist on Home, the trial notice and the team invite message, in
/// every language the app has. Spread into each language's table.
library;

const Map<String, String> onboardingHi = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'सबसे तेज़, और कोई पासवर्ड याद नहीं रखना। आपकी टीम भी ऐसे ही जुड़ती है।',
  'Use a username and password instead': 'इसकी जगह यूज़रनेम और पासवर्ड से',
  'Get your first site running': 'अपनी पहली साइट चालू करें',
  'Your site is running on FieldOS': 'आपकी साइट FieldOS पर चल रही है',
  'Every step done. Your evening report will be ready on time.':
      'सब काम हो गए। आपकी शाम की रिपोर्ट समय पर तैयार होगी।',
  '{done} of {total} done · about 5 minutes': '{total} में से {done} हो गए · लगभग 5 मिनट',
  'Getting started': 'शुरुआत',
  'Hide': 'छिपाएँ',
  'Add your first site': 'अपनी पहली साइट जोड़ें',
  "Mark today's attendance": 'आज की हाज़िरी लगाएँ',
  "Send today's daily report": 'आज की दैनिक रिपोर्ट भेजें',
  'Invite your team': 'अपनी टीम को बुलाएँ',
  'Its name is enough to start.': 'शुरू करने के लिए बस उसका नाम काफ़ी है।',
  'Who came to site today. Wages work out from it.': 'आज साइट पर कौन आया। मज़दूरी इसी से निकलती है।',
  'Speak it in your language; FieldOS writes it up.': 'अपनी भाषा में बोलें; FieldOS उसे लिख देता है।',
  'Send the join code to your engineers on WhatsApp.': 'अपने इंजीनियरों को WhatsApp पर जॉइन कोड भेजें।',
  'Send the invite': 'न्योता भेजें',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp या SMS पर भेजें। इसमें ऐप का लिंक और स्टेप्स हैं।',
  'Join {company} on FieldOS, our site app.': 'FieldOS पर {company} से जुड़ें, यह हमारा साइट ऐप है।',
  '1. Install it: {link}': '1. इसे इंस्टॉल करें: {link}',
  '2. Sign in with Google.': '2. Google से साइन इन करें।',
  '3. Tap "Join with a code" and enter {code}': '3. "कोड से जुड़ें" पर टैप करें और {code} डालें',
  'our company': 'हमारी कंपनी',
  'Your free trial ends today': 'आपका फ़्री ट्रायल आज खत्म होता है',
  'Free trial: 1 day left': 'फ़्री ट्रायल: 1 दिन बाकी',
  'Free trial: {n} days left': 'फ़्री ट्रायल: {n} दिन बाकी',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'उसके बाद आपका प्लान अपने-आप शुरू हो जाता है। रोकने के लिए उससे पहले {path} में रद्द करें।',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'आपका ट्रायल आगे नहीं बढ़ेगा। साइटें चालू रखने के लिए एक प्लान चुनें।',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'इस अकाउंट पर कोई कंपनी प्लान नहीं मिला। मालिक से मिले कोड से अपनी कंपनी से जुड़ें, या उस ईमेल से साइन इन करें जिस पर प्लान है।',
  'Sign in to your company first, then FieldOS opens by itself.':
      'पहले अपनी कंपनी में साइन इन करें, फिर FieldOS अपने-आप खुल जाएगा।',
};

const Map<String, String> onboardingTe = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'చాలా త్వరగా, పాస్‌వర్డ్ గుర్తుపెట్టుకోవాల్సిన అవసరం లేదు. మీ టీమ్ కూడా ఇలాగే చేరుతుంది.',
  'Use a username and password instead': 'బదులుగా యూజర్‌నేమ్, పాస్‌వర్డ్‌తో',
  'Get your first site running': 'మీ మొదటి సైట్‌ను మొదలుపెట్టండి',
  'Your site is running on FieldOS': 'మీ సైట్ FieldOSలో నడుస్తోంది',
  'Every step done. Your evening report will be ready on time.':
      'అన్ని స్టెప్స్ పూర్తయ్యాయి. మీ సాయంత్రం రిపోర్ట్ సమయానికి సిద్ధంగా ఉంటుంది.',
  '{done} of {total} done · about 5 minutes': '{total}లో {done} పూర్తయ్యాయి · సుమారు 5 నిమిషాలు',
  'Getting started': 'మొదలుపెట్టడం',
  'Hide': 'దాచండి',
  'Add your first site': 'మీ మొదటి సైట్‌ను జోడించండి',
  "Mark today's attendance": 'ఈరోజు హాజరు వేయండి',
  "Send today's daily report": 'ఈరోజు రోజువారీ రిపోర్ట్ పంపండి',
  'Invite your team': 'మీ టీమ్‌ను ఆహ్వానించండి',
  'Its name is enough to start.': 'మొదలుపెట్టడానికి దాని పేరు చాలు.',
  'Who came to site today. Wages work out from it.': 'ఈరోజు సైట్‌కు ఎవరు వచ్చారు. కూలీ దీని నుంచే లెక్కవుతుంది.',
  'Speak it in your language; FieldOS writes it up.': 'మీ భాషలో చెప్పండి; FieldOS రాసేస్తుంది.',
  'Send the join code to your engineers on WhatsApp.': 'మీ ఇంజనీర్లకు WhatsAppలో జాయిన్ కోడ్ పంపండి.',
  'Send the invite': 'ఆహ్వానం పంపండి',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp లేదా SMSలో పంపండి. అందులో యాప్ లింక్, స్టెప్స్ ఉంటాయి.',
  'Join {company} on FieldOS, our site app.': 'FieldOSలో {company}లో చేరండి, ఇది మా సైట్ యాప్.',
  '1. Install it: {link}': '1. ఇన్‌స్టాల్ చేయండి: {link}',
  '2. Sign in with Google.': '2. Googleతో సైన్ ఇన్ చేయండి.',
  '3. Tap "Join with a code" and enter {code}': '3. "కోడ్‌తో చేరండి" నొక్కి {code} ఎంటర్ చేయండి',
  'our company': 'మా కంపెనీ',
  'Your free trial ends today': 'మీ ఫ్రీ ట్రయల్ ఈరోజుతో ముగుస్తుంది',
  'Free trial: 1 day left': 'ఫ్రీ ట్రయల్: 1 రోజు మిగిలి ఉంది',
  'Free trial: {n} days left': 'ఫ్రీ ట్రయల్: {n} రోజులు మిగిలి ఉన్నాయి',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'ఆ తర్వాత మీ ప్లాన్ దానంతట అదే మొదలవుతుంది. ఆపాలంటే, అంతకు ముందే {path}లో క్యాన్సిల్ చేయండి.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'మీ ట్రయల్ రెన్యూ కాదు. మీ సైట్లు నడుస్తూ ఉండాలంటే ఒక ప్లాన్ ఎంచుకోండి.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'ఈ అకౌంట్‌కు కంపెనీ ప్లాన్ ఏదీ కనబడలేదు. ఓనర్ ఇచ్చిన కోడ్‌తో మీ కంపెనీలో చేరండి, లేదా ప్లాన్ ఉన్న ఈమెయిల్‌తో సైన్ ఇన్ చేయండి.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'ముందు మీ కంపెనీకి సైన్ ఇన్ చేయండి, తర్వాత FieldOS దానంతట అదే తెరుచుకుంటుంది.',
};

const Map<String, String> onboardingTa = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'மிக விரைவானது, நினைவில் வைக்க கடவுச்சொல் இல்லை. உங்கள் குழுவும் இதே வழியில் சேரும்.',
  'Use a username and password instead': 'பதிலாக பயனர்பெயர், கடவுச்சொல் பயன்படுத்து',
  'Get your first site running': 'உங்கள் முதல் தளத்தைத் தொடங்குங்கள்',
  'Your site is running on FieldOS': 'உங்கள் தளம் FieldOS-இல் இயங்குகிறது',
  'Every step done. Your evening report will be ready on time.':
      'எல்லா படிகளும் முடிந்தன. உங்கள் மாலை அறிக்கை நேரத்துக்குத் தயாராக இருக்கும்.',
  '{done} of {total} done · about 5 minutes': '{total}-இல் {done} முடிந்தது · சுமார் 5 நிமிடம்',
  'Getting started': 'தொடக்கம்',
  'Hide': 'மறை',
  'Add your first site': 'உங்கள் முதல் தளத்தைச் சேர்க்கவும்',
  "Mark today's attendance": 'இன்றைய வருகையைப் பதிவு செய்யவும்',
  "Send today's daily report": 'இன்றைய தினசரி அறிக்கையை அனுப்பவும்',
  'Invite your team': 'உங்கள் குழுவை அழைக்கவும்',
  'Its name is enough to start.': 'தொடங்க அதன் பெயர் போதும்.',
  'Who came to site today. Wages work out from it.': 'இன்று தளத்துக்கு யார் வந்தார்கள். கூலி இதிலிருந்தே கணக்காகும்.',
  'Speak it in your language; FieldOS writes it up.': 'உங்கள் மொழியில் சொல்லுங்கள்; FieldOS அதை எழுதும்.',
  'Send the join code to your engineers on WhatsApp.': 'உங்கள் பொறியாளர்களுக்கு WhatsApp-இல் சேரும் குறியீட்டை அனுப்பவும்.',
  'Send the invite': 'அழைப்பை அனுப்பு',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp அல்லது SMS-இல் அனுப்பவும். அதில் ஆப் இணைப்பும் படிகளும் உள்ளன.',
  'Join {company} on FieldOS, our site app.': 'FieldOS-இல் {company}-இல் சேருங்கள், இது எங்கள் தள ஆப்.',
  '1. Install it: {link}': '1. நிறுவவும்: {link}',
  '2. Sign in with Google.': '2. Google மூலம் உள்நுழையவும்.',
  '3. Tap "Join with a code" and enter {code}': '3. "குறியீட்டுடன் சேர்" என்பதைத் தட்டி {code} உள்ளிடவும்',
  'our company': 'எங்கள் நிறுவனம்',
  'Your free trial ends today': 'உங்கள் இலவச சோதனை இன்று முடிகிறது',
  'Free trial: 1 day left': 'இலவச சோதனை: 1 நாள் மீதம்',
  'Free trial: {n} days left': 'இலவச சோதனை: {n} நாட்கள் மீதம்',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'அதன் பிறகு உங்கள் திட்டம் தானாகத் தொடங்கும். நிறுத்த, அதற்கு முன் {path}-இல் ரத்து செய்யவும்.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'உங்கள் சோதனை புதுப்பிக்கப்படாது. தளங்கள் தொடர ஒரு திட்டத்தைத் தேர்ந்தெடுக்கவும்.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'இந்தக் கணக்கில் நிறுவனத் திட்டம் எதுவும் இல்லை. உரிமையாளர் தந்த குறியீட்டுடன் உங்கள் நிறுவனத்தில் சேரவும், அல்லது திட்டம் உள்ள மின்னஞ்சலுடன் உள்நுழையவும்.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'முதலில் உங்கள் நிறுவனத்தில் உள்நுழையவும், பிறகு FieldOS தானாகத் திறக்கும்.',
};

const Map<String, String> onboardingKn = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'ಅತಿ ವೇಗ, ನೆನಪಿಡಲು ಪಾಸ್‌ವರ್ಡ್ ಇಲ್ಲ. ನಿಮ್ಮ ತಂಡವೂ ಹೀಗೆಯೇ ಸೇರುತ್ತದೆ.',
  'Use a username and password instead': 'ಬದಲಿಗೆ ಯೂಸರ್‌ನೇಮ್ ಮತ್ತು ಪಾಸ್‌ವರ್ಡ್ ಬಳಸಿ',
  'Get your first site running': 'ನಿಮ್ಮ ಮೊದಲ ಸೈಟ್ ಶುರು ಮಾಡಿ',
  'Your site is running on FieldOS': 'ನಿಮ್ಮ ಸೈಟ್ FieldOS ನಲ್ಲಿ ನಡೆಯುತ್ತಿದೆ',
  'Every step done. Your evening report will be ready on time.':
      'ಎಲ್ಲಾ ಹಂತಗಳು ಮುಗಿದಿವೆ. ನಿಮ್ಮ ಸಂಜೆಯ ವರದಿ ಸಮಯಕ್ಕೆ ಸಿದ್ಧವಾಗಿರುತ್ತದೆ.',
  '{done} of {total} done · about 5 minutes': '{total} ರಲ್ಲಿ {done} ಆಯಿತು · ಸುಮಾರು 5 ನಿಮಿಷ',
  'Getting started': 'ಶುರುವಾತು',
  'Hide': 'ಮರೆಮಾಡಿ',
  'Add your first site': 'ನಿಮ್ಮ ಮೊದಲ ಸೈಟ್ ಸೇರಿಸಿ',
  "Mark today's attendance": 'ಇಂದಿನ ಹಾಜರಾತಿ ಹಾಕಿ',
  "Send today's daily report": 'ಇಂದಿನ ದಿನದ ವರದಿ ಕಳುಹಿಸಿ',
  'Invite your team': 'ನಿಮ್ಮ ತಂಡವನ್ನು ಆಹ್ವಾನಿಸಿ',
  'Its name is enough to start.': 'ಶುರು ಮಾಡಲು ಅದರ ಹೆಸರು ಸಾಕು.',
  'Who came to site today. Wages work out from it.': 'ಇಂದು ಸೈಟ್‌ಗೆ ಯಾರು ಬಂದರು. ಕೂಲಿ ಇದರಿಂದಲೇ ಲೆಕ್ಕವಾಗುತ್ತದೆ.',
  'Speak it in your language; FieldOS writes it up.': 'ನಿಮ್ಮ ಭಾಷೆಯಲ್ಲಿ ಹೇಳಿ; FieldOS ಅದನ್ನು ಬರೆಯುತ್ತದೆ.',
  'Send the join code to your engineers on WhatsApp.': 'ನಿಮ್ಮ ಎಂಜಿನಿಯರ್‌ಗಳಿಗೆ WhatsApp ನಲ್ಲಿ ಜಾಯಿನ್ ಕೋಡ್ ಕಳುಹಿಸಿ.',
  'Send the invite': 'ಆಹ್ವಾನ ಕಳುಹಿಸಿ',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp ಅಥವಾ SMS ನಲ್ಲಿ ಕಳುಹಿಸಿ. ಅದರಲ್ಲಿ ಆ್ಯಪ್ ಲಿಂಕ್ ಮತ್ತು ಹಂತಗಳಿವೆ.',
  'Join {company} on FieldOS, our site app.': 'FieldOS ನಲ್ಲಿ {company} ಗೆ ಸೇರಿ, ಇದು ನಮ್ಮ ಸೈಟ್ ಆ್ಯಪ್.',
  '1. Install it: {link}': '1. ಇನ್‌ಸ್ಟಾಲ್ ಮಾಡಿ: {link}',
  '2. Sign in with Google.': '2. Google ನಿಂದ ಸೈನ್ ಇನ್ ಮಾಡಿ.',
  '3. Tap "Join with a code" and enter {code}': '3. "ಕೋಡ್‌ನಿಂದ ಸೇರಿ" ಒತ್ತಿ {code} ನಮೂದಿಸಿ',
  'our company': 'ನಮ್ಮ ಕಂಪನಿ',
  'Your free trial ends today': 'ನಿಮ್ಮ ಉಚಿತ ಟ್ರಯಲ್ ಇಂದು ಮುಗಿಯುತ್ತದೆ',
  'Free trial: 1 day left': 'ಉಚಿತ ಟ್ರಯಲ್: 1 ದಿನ ಬಾಕಿ',
  'Free trial: {n} days left': 'ಉಚಿತ ಟ್ರಯಲ್: {n} ದಿನ ಬಾಕಿ',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'ಅದರ ನಂತರ ನಿಮ್ಮ ಪ್ಲಾನ್ ತಾನಾಗಿಯೇ ಶುರುವಾಗುತ್ತದೆ. ನಿಲ್ಲಿಸಲು, ಅದಕ್ಕೂ ಮೊದಲು {path} ನಲ್ಲಿ ರದ್ದು ಮಾಡಿ.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'ನಿಮ್ಮ ಟ್ರಯಲ್ ನವೀಕರಣವಾಗುವುದಿಲ್ಲ. ಸೈಟ್‌ಗಳು ನಡೆಯುತ್ತಿರಲು ಒಂದು ಪ್ಲಾನ್ ಆರಿಸಿ.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'ಈ ಖಾತೆಗೆ ಯಾವುದೇ ಕಂಪನಿ ಪ್ಲಾನ್ ಸಿಗಲಿಲ್ಲ. ಮಾಲೀಕರು ಕೊಟ್ಟ ಕೋಡ್‌ನಿಂದ ನಿಮ್ಮ ಕಂಪನಿಗೆ ಸೇರಿ, ಅಥವಾ ಪ್ಲಾನ್ ಇರುವ ಇಮೇಲ್‌ನಿಂದ ಸೈನ್ ಇನ್ ಮಾಡಿ.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'ಮೊದಲು ನಿಮ್ಮ ಕಂಪನಿಗೆ ಸೈನ್ ಇನ್ ಮಾಡಿ, ನಂತರ FieldOS ತಾನಾಗಿಯೇ ತೆರೆಯುತ್ತದೆ.',
};

const Map<String, String> onboardingMr = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'सर्वात जलद, आणि पासवर्ड लक्षात ठेवायची गरज नाही. तुमची टीमही अशीच जॉइन होते.',
  'Use a username and password instead': 'त्याऐवजी युजरनेम आणि पासवर्ड वापरा',
  'Get your first site running': 'तुमची पहिली साइट सुरू करा',
  'Your site is running on FieldOS': 'तुमची साइट FieldOS वर चालू आहे',
  'Every step done. Your evening report will be ready on time.':
      'सगळ्या पायऱ्या झाल्या. तुमचा संध्याकाळचा अहवाल वेळेवर तयार असेल.',
  '{done} of {total} done · about 5 minutes': '{total} पैकी {done} झाले · सुमारे 5 मिनिटे',
  'Getting started': 'सुरुवात',
  'Hide': 'लपवा',
  'Add your first site': 'तुमची पहिली साइट जोडा',
  "Mark today's attendance": 'आजची हजेरी लावा',
  "Send today's daily report": 'आजचा दैनिक अहवाल पाठवा',
  'Invite your team': 'तुमच्या टीमला बोलवा',
  'Its name is enough to start.': 'सुरू करायला तिचे नाव पुरेसे आहे.',
  'Who came to site today. Wages work out from it.': 'आज साइटवर कोण आले. मजुरी यावरूनच निघते.',
  'Speak it in your language; FieldOS writes it up.': 'तुमच्या भाषेत बोला; FieldOS ते लिहून देते.',
  'Send the join code to your engineers on WhatsApp.': 'तुमच्या इंजिनिअरना WhatsApp वर जॉइन कोड पाठवा.',
  'Send the invite': 'आमंत्रण पाठवा',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp किंवा SMS वर पाठवा. त्यात अ‍ॅपची लिंक आणि पायऱ्या आहेत.',
  'Join {company} on FieldOS, our site app.': 'FieldOS वर {company} मध्ये जॉइन व्हा, हे आमचे साइट अ‍ॅप आहे.',
  '1. Install it: {link}': '1. इन्स्टॉल करा: {link}',
  '2. Sign in with Google.': '2. Google ने साइन इन करा.',
  '3. Tap "Join with a code" and enter {code}': '3. "कोडने जॉइन करा" वर टॅप करा आणि {code} टाका',
  'our company': 'आमची कंपनी',
  'Your free trial ends today': 'तुमची फ्री ट्रायल आज संपते',
  'Free trial: 1 day left': 'फ्री ट्रायल: 1 दिवस बाकी',
  'Free trial: {n} days left': 'फ्री ट्रायल: {n} दिवस बाकी',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'त्यानंतर तुमचा प्लॅन आपोआप सुरू होतो. थांबवायचा असल्यास, त्याआधी {path} मध्ये रद्द करा.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'तुमची ट्रायल पुढे वाढणार नाही. साइट्स चालू ठेवण्यासाठी एक प्लॅन निवडा.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'या अकाउंटवर कोणताही कंपनी प्लॅन सापडला नाही. मालकाकडून मिळालेल्या कोडने तुमच्या कंपनीत जॉइन व्हा, किंवा ज्या ईमेलवर प्लॅन आहे त्याने साइन इन करा.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'आधी तुमच्या कंपनीत साइन इन करा, मग FieldOS आपोआप उघडेल.',
};

const Map<String, String> onboardingEs = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'Lo más rápido, y sin contraseña que recordar. Tu equipo se une igual.',
  'Use a username and password instead': 'Usar usuario y contraseña',
  'Get your first site running': 'Pon en marcha tu primera obra',
  'Your site is running on FieldOS': 'Tu obra ya funciona en FieldOS',
  'Every step done. Your evening report will be ready on time.':
      'Todo listo. Tu reporte de la tarde estará a tiempo.',
  '{done} of {total} done · about 5 minutes': '{done} de {total} listos · unos 5 minutos',
  'Getting started': 'Primeros pasos',
  'Hide': 'Ocultar',
  'Add your first site': 'Agrega tu primera obra',
  "Mark today's attendance": 'Marca la asistencia de hoy',
  "Send today's daily report": 'Envía el reporte diario de hoy',
  'Invite your team': 'Invita a tu equipo',
  'Its name is enough to start.': 'Con el nombre basta para empezar.',
  'Who came to site today. Wages work out from it.': 'Quién vino hoy a la obra. Los pagos salen de aquí.',
  'Speak it in your language; FieldOS writes it up.': 'Dilo en tu idioma; FieldOS lo redacta.',
  'Send the join code to your engineers on WhatsApp.': 'Envía el código de acceso a tus ingenieros por WhatsApp.',
  'Send the invite': 'Enviar la invitación',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'Envíala por WhatsApp o SMS. Lleva el enlace de la app y los pasos.',
  'Join {company} on FieldOS, our site app.': 'Únete a {company} en FieldOS, nuestra app de obra.',
  '1. Install it: {link}': '1. Instálala: {link}',
  '2. Sign in with Google.': '2. Inicia sesión con Google.',
  '3. Tap "Join with a code" and enter {code}': '3. Toca "Unirme con un código" y escribe {code}',
  'our company': 'nuestra empresa',
  'Your free trial ends today': 'Tu prueba gratis termina hoy',
  'Free trial: 1 day left': 'Prueba gratis: queda 1 día',
  'Free trial: {n} days left': 'Prueba gratis: quedan {n} días',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'Después tu plan empieza solo. Para evitarlo, cancela en {path} antes.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'Tu prueba no se renovará. Elige un plan para seguir con tus obras.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'No hay un plan de empresa en esta cuenta. Únete a tu empresa con el código del dueño, o inicia sesión con el correo del plan.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'Primero inicia sesión en tu empresa; luego FieldOS se abre solo.',
};

const Map<String, String> onboardingMs = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'Paling cepat, dan tiada kata laluan untuk diingat. Pasukan anda sertai dengan cara yang sama.',
  'Use a username and password instead': 'Guna nama pengguna dan kata laluan',
  'Get your first site running': 'Mulakan tapak pertama anda',
  'Your site is running on FieldOS': 'Tapak anda sudah berjalan di FieldOS',
  'Every step done. Your evening report will be ready on time.':
      'Semua langkah selesai. Laporan petang anda akan siap tepat pada masanya.',
  '{done} of {total} done · about 5 minutes': '{done} daripada {total} selesai · kira-kira 5 minit',
  'Getting started': 'Bermula',
  'Hide': 'Sembunyi',
  'Add your first site': 'Tambah tapak pertama anda',
  "Mark today's attendance": 'Tanda kehadiran hari ini',
  "Send today's daily report": 'Hantar laporan harian hari ini',
  'Invite your team': 'Jemput pasukan anda',
  'Its name is enough to start.': 'Namanya sudah cukup untuk bermula.',
  'Who came to site today. Wages work out from it.': 'Siapa datang ke tapak hari ini. Upah dikira daripadanya.',
  'Speak it in your language; FieldOS writes it up.': 'Sebut dalam bahasa anda; FieldOS akan menulisnya.',
  'Send the join code to your engineers on WhatsApp.': 'Hantar kod sertai kepada jurutera anda di WhatsApp.',
  'Send the invite': 'Hantar jemputan',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'Hantar di WhatsApp atau SMS. Ia ada pautan aplikasi dan langkah-langkahnya.',
  'Join {company} on FieldOS, our site app.': 'Sertai {company} di FieldOS, aplikasi tapak kami.',
  '1. Install it: {link}': '1. Pasang: {link}',
  '2. Sign in with Google.': '2. Log masuk dengan Google.',
  '3. Tap "Join with a code" and enter {code}': '3. Ketik "Sertai dengan kod" dan masukkan {code}',
  'our company': 'syarikat kami',
  'Your free trial ends today': 'Percubaan percuma anda tamat hari ini',
  'Free trial: 1 day left': 'Percubaan percuma: tinggal 1 hari',
  'Free trial: {n} days left': 'Percubaan percuma: tinggal {n} hari',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'Selepas itu pelan anda bermula sendiri. Untuk menghentikannya, batalkan di {path} sebelum itu.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'Percubaan anda tidak akan diperbaharui. Pilih pelan untuk meneruskan tapak anda.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'Tiada pelan syarikat untuk akaun ini. Sertai syarikat anda dengan kod daripada pemiliknya, atau log masuk dengan e-mel pelan itu.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'Log masuk ke syarikat anda dahulu, kemudian FieldOS dibuka dengan sendirinya.',
};

const Map<String, String> onboardingZh = {
  'Quickest, and no password to remember. Your team joins the same way.': '最快，也不用记密码。你的团队也用同样的方式加入。',
  'Use a username and password instead': '改用用户名和密码',
  'Get your first site running': '让你的第一个工地运转起来',
  'Your site is running on FieldOS': '你的工地已在 FieldOS 上运转',
  'Every step done. Your evening report will be ready on time.': '每一步都完成了。你的晚间报告会按时准备好。',
  '{done} of {total} done · about 5 minutes': '已完成 {done}/{total} · 约 5 分钟',
  'Getting started': '入门',
  'Hide': '隐藏',
  'Add your first site': '添加你的第一个工地',
  "Mark today's attendance": '记录今天的考勤',
  "Send today's daily report": '发送今天的每日报告',
  'Invite your team': '邀请你的团队',
  'Its name is enough to start.': '只要名称就可以开始。',
  'Who came to site today. Wages work out from it.': '今天谁来了工地。工资由此算出。',
  'Speak it in your language; FieldOS writes it up.': '用你的语言说出来，FieldOS 帮你写好。',
  'Send the join code to your engineers on WhatsApp.': '通过 WhatsApp 把加入码发给你的工程师。',
  'Send the invite': '发送邀请',
  'Send it on WhatsApp or SMS. It has the app link and the steps.': '通过 WhatsApp 或短信发送。里面有应用链接和步骤。',
  'Join {company} on FieldOS, our site app.': '在 FieldOS 加入 {company}，这是我们的工地应用。',
  '1. Install it: {link}': '1. 安装：{link}',
  '2. Sign in with Google.': '2. 用 Google 登录。',
  '3. Tap "Join with a code" and enter {code}': '3. 点“用加入码加入”，输入 {code}',
  'our company': '我们公司',
  'Your free trial ends today': '你的免费试用今天结束',
  'Free trial: 1 day left': '免费试用：还剩 1 天',
  'Free trial: {n} days left': '免费试用：还剩 {n} 天',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      '之后你的方案会自动开始。如要停止，请在此之前到 {path} 取消。',
  'Your trial will not renew. Choose a plan to keep your sites going.': '你的试用不会续订。选择一个方案，让工地继续运转。',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      '这个账户没有公司方案。用老板给的加入码加入你的公司，或用方案所在的邮箱登录。',
  'Sign in to your company first, then FieldOS opens by itself.': '先登录你的公司，FieldOS 就会自动打开。',
};

const Map<String, String> onboardingAr = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'الأسرع، وبدون كلمة مرور تتذكرها. فريقك ينضم بالطريقة نفسها.',
  'Use a username and password instead': 'استخدم اسم مستخدم وكلمة مرور بدلاً من ذلك',
  'Get your first site running': 'شغّل موقعك الأول',
  'Your site is running on FieldOS': 'موقعك يعمل الآن على FieldOS',
  'Every step done. Your evening report will be ready on time.': 'اكتملت كل الخطوات. سيكون تقريرك المسائي جاهزاً في موعده.',
  '{done} of {total} done · about 5 minutes': 'اكتمل {done} من {total} · حوالي 5 دقائق',
  'Getting started': 'البداية',
  'Hide': 'إخفاء',
  'Add your first site': 'أضف موقعك الأول',
  "Mark today's attendance": 'سجّل حضور اليوم',
  "Send today's daily report": 'أرسل التقرير اليومي لليوم',
  'Invite your team': 'ادعُ فريقك',
  'Its name is enough to start.': 'يكفي اسمه للبدء.',
  'Who came to site today. Wages work out from it.': 'من حضر إلى الموقع اليوم. تُحسب الأجور منه.',
  'Speak it in your language; FieldOS writes it up.': 'قُلها بلغتك، ويكتبها FieldOS.',
  'Send the join code to your engineers on WhatsApp.': 'أرسل رمز الانضمام إلى مهندسيك على WhatsApp.',
  'Send the invite': 'أرسل الدعوة',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'أرسلها عبر WhatsApp أو رسالة نصية. فيها رابط التطبيق والخطوات.',
  'Join {company} on FieldOS, our site app.': 'انضم إلى {company} على FieldOS، تطبيق مواقعنا.',
  '1. Install it: {link}': '1. ثبّته: {link}',
  '2. Sign in with Google.': '2. سجّل الدخول باستخدام Google.',
  '3. Tap "Join with a code" and enter {code}': '3. اضغط "انضم برمز" وأدخل {code}',
  'our company': 'شركتنا',
  'Your free trial ends today': 'تنتهي تجربتك المجانية اليوم',
  'Free trial: 1 day left': 'التجربة المجانية: بقي يوم واحد',
  'Free trial: {n} days left': 'التجربة المجانية: بقي {n} أيام',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'بعد ذلك تبدأ خطتك تلقائياً. لإيقافها، ألغِها من {path} قبل ذلك.',
  'Your trial will not renew. Choose a plan to keep your sites going.': 'لن تتجدد تجربتك. اختر خطة لتستمر مواقعك.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'لا توجد خطة شركة لهذا الحساب. انضم إلى شركتك بالرمز من مالكها، أو سجّل الدخول بالبريد الذي عليه الخطة.',
  'Sign in to your company first, then FieldOS opens by itself.': 'سجّل الدخول إلى شركتك أولاً، ثم يفتح FieldOS تلقائياً.',
};

const Map<String, String> onboardingUr = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'سب سے تیز، اور کوئی پاس ورڈ یاد نہیں رکھنا۔ آپ کی ٹیم بھی ایسے ہی جوائن کرتی ہے۔',
  'Use a username and password instead': 'اس کے بجائے یوزر نیم اور پاس ورڈ استعمال کریں',
  'Get your first site running': 'اپنی پہلی سائٹ چالو کریں',
  'Your site is running on FieldOS': 'آپ کی سائٹ FieldOS پر چل رہی ہے',
  'Every step done. Your evening report will be ready on time.': 'سب مرحلے مکمل۔ آپ کی شام کی رپورٹ وقت پر تیار ہوگی۔',
  '{done} of {total} done · about 5 minutes': '{total} میں سے {done} مکمل · تقریباً 5 منٹ',
  'Getting started': 'آغاز',
  'Hide': 'چھپائیں',
  'Add your first site': 'اپنی پہلی سائٹ شامل کریں',
  "Mark today's attendance": 'آج کی حاضری لگائیں',
  "Send today's daily report": 'آج کی روزانہ رپورٹ بھیجیں',
  'Invite your team': 'اپنی ٹیم کو بلائیں',
  'Its name is enough to start.': 'شروع کرنے کے لیے اس کا نام کافی ہے۔',
  'Who came to site today. Wages work out from it.': 'آج سائٹ پر کون آیا۔ مزدوری اسی سے نکلتی ہے۔',
  'Speak it in your language; FieldOS writes it up.': 'اپنی زبان میں بولیں؛ FieldOS اسے لکھ دیتا ہے۔',
  'Send the join code to your engineers on WhatsApp.': 'اپنے انجینئرز کو WhatsApp پر جوائن کوڈ بھیجیں۔',
  'Send the invite': 'دعوت بھیجیں',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp یا SMS پر بھیجیں۔ اس میں ایپ کا لنک اور مراحل ہیں۔',
  'Join {company} on FieldOS, our site app.': 'FieldOS پر {company} جوائن کریں، یہ ہماری سائٹ ایپ ہے۔',
  '1. Install it: {link}': '1. انسٹال کریں: {link}',
  '2. Sign in with Google.': '2. Google سے سائن ان کریں۔',
  '3. Tap "Join with a code" and enter {code}': '3. "کوڈ سے جوائن کریں" پر ٹیپ کریں اور {code} درج کریں',
  'our company': 'ہماری کمپنی',
  'Your free trial ends today': 'آپ کا مفت ٹرائل آج ختم ہوتا ہے',
  'Free trial: 1 day left': 'مفت ٹرائل: 1 دن باقی',
  'Free trial: {n} days left': 'مفت ٹرائل: {n} دن باقی',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'اس کے بعد آپ کا پلان خود شروع ہو جاتا ہے۔ روکنے کے لیے اس سے پہلے {path} میں منسوخ کریں۔',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'آپ کا ٹرائل آگے نہیں بڑھے گا۔ سائٹیں چالو رکھنے کے لیے ایک پلان چنیں۔',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'اس اکاؤنٹ پر کوئی کمپنی پلان نہیں ملا۔ مالک سے ملے کوڈ سے اپنی کمپنی جوائن کریں، یا اس ای میل سے سائن ان کریں جس پر پلان ہے۔',
  'Sign in to your company first, then FieldOS opens by itself.':
      'پہلے اپنی کمپنی میں سائن ان کریں، پھر FieldOS خود کھل جائے گا۔',
};

const Map<String, String> onboardingMl = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'ഏറ്റവും വേഗം, ഓർക്കാൻ പാസ്‌വേഡില്ല. നിങ്ങളുടെ ടീമും ഇങ്ങനെതന്നെ ചേരും.',
  'Use a username and password instead': 'പകരം യൂസർനെയിമും പാസ്‌വേഡും ഉപയോഗിക്കുക',
  'Get your first site running': 'നിങ്ങളുടെ ആദ്യ സൈറ്റ് തുടങ്ങുക',
  'Your site is running on FieldOS': 'നിങ്ങളുടെ സൈറ്റ് FieldOS-ൽ പ്രവർത്തിക്കുന്നു',
  'Every step done. Your evening report will be ready on time.':
      'എല്ലാ ഘട്ടവും കഴിഞ്ഞു. നിങ്ങളുടെ വൈകുന്നേര റിപ്പോർട്ട് സമയത്ത് തയ്യാറാകും.',
  '{done} of {total} done · about 5 minutes': '{total}-ൽ {done} കഴിഞ്ഞു · ഏകദേശം 5 മിനിറ്റ്',
  'Getting started': 'തുടക്കം',
  'Hide': 'മറയ്ക്കുക',
  'Add your first site': 'നിങ്ങളുടെ ആദ്യ സൈറ്റ് ചേർക്കുക',
  "Mark today's attendance": 'ഇന്നത്തെ ഹാജർ രേഖപ്പെടുത്തുക',
  "Send today's daily report": 'ഇന്നത്തെ ദിവസ റിപ്പോർട്ട് അയയ്ക്കുക',
  'Invite your team': 'നിങ്ങളുടെ ടീമിനെ ക്ഷണിക്കുക',
  'Its name is enough to start.': 'തുടങ്ങാൻ അതിന്റെ പേര് മതി.',
  'Who came to site today. Wages work out from it.': 'ഇന്ന് സൈറ്റിൽ ആരൊക്കെ വന്നു. കൂലി ഇതിൽ നിന്നാണ് കണക്കാക്കുന്നത്.',
  'Speak it in your language; FieldOS writes it up.': 'നിങ്ങളുടെ ഭാഷയിൽ പറയൂ; FieldOS അത് എഴുതും.',
  'Send the join code to your engineers on WhatsApp.': 'നിങ്ങളുടെ എഞ്ചിനീയർമാർക്ക് WhatsApp-ൽ ജോയിൻ കോഡ് അയയ്ക്കുക.',
  'Send the invite': 'ക്ഷണം അയയ്ക്കുക',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'WhatsApp-ലോ SMS-ലോ അയയ്ക്കുക. അതിൽ ആപ്പ് ലിങ്കും ഘട്ടങ്ങളുമുണ്ട്.',
  'Join {company} on FieldOS, our site app.': 'FieldOS-ൽ {company}-ൽ ചേരൂ, ഇത് ഞങ്ങളുടെ സൈറ്റ് ആപ്പാണ്.',
  '1. Install it: {link}': '1. ഇൻസ്റ്റാൾ ചെയ്യുക: {link}',
  '2. Sign in with Google.': '2. Google ഉപയോഗിച്ച് സൈൻ ഇൻ ചെയ്യുക.',
  '3. Tap "Join with a code" and enter {code}': '3. "കോഡ് ഉപയോഗിച്ച് ചേരുക" ടാപ്പ് ചെയ്ത് {code} നൽകുക',
  'our company': 'ഞങ്ങളുടെ കമ്പനി',
  'Your free trial ends today': 'നിങ്ങളുടെ സൗജന്യ ട്രയൽ ഇന്ന് അവസാനിക്കും',
  'Free trial: 1 day left': 'സൗജന്യ ട്രയൽ: 1 ദിവസം ബാക്കി',
  'Free trial: {n} days left': 'സൗജന്യ ട്രയൽ: {n} ദിവസം ബാക്കി',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'അതിനുശേഷം നിങ്ങളുടെ പ്ലാൻ സ്വയം തുടങ്ങും. നിർത്താൻ, അതിനുമുമ്പ് {path}-ൽ റദ്ദാക്കുക.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'നിങ്ങളുടെ ട്രയൽ പുതുക്കില്ല. സൈറ്റുകൾ തുടരാൻ ഒരു പ്ലാൻ തിരഞ്ഞെടുക്കുക.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'ഈ അക്കൗണ്ടിൽ കമ്പനി പ്ലാൻ ഒന്നും കണ്ടില്ല. ഉടമ നൽകിയ കോഡ് ഉപയോഗിച്ച് നിങ്ങളുടെ കമ്പനിയിൽ ചേരുക, അല്ലെങ്കിൽ പ്ലാൻ ഉള്ള ഇമെയിൽ ഉപയോഗിച്ച് സൈൻ ഇൻ ചെയ്യുക.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'ആദ്യം നിങ്ങളുടെ കമ്പനിയിൽ സൈൻ ഇൻ ചെയ്യുക, പിന്നെ FieldOS സ്വയം തുറക്കും.',
};

const Map<String, String> onboardingPl = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'Najszybciej i bez hasła do zapamiętania. Twój zespół dołącza tak samo.',
  'Use a username and password instead': 'Użyj nazwy użytkownika i hasła',
  'Get your first site running': 'Uruchom swoją pierwszą budowę',
  'Your site is running on FieldOS': 'Twoja budowa działa w FieldOS',
  'Every step done. Your evening report will be ready on time.':
      'Wszystkie kroki gotowe. Wieczorny raport będzie na czas.',
  '{done} of {total} done · about 5 minutes': '{done} z {total} gotowe · około 5 minut',
  'Getting started': 'Pierwsze kroki',
  'Hide': 'Ukryj',
  'Add your first site': 'Dodaj pierwszą budowę',
  "Mark today's attendance": 'Zaznacz dzisiejszą obecność',
  "Send today's daily report": 'Wyślij dzisiejszy raport dzienny',
  'Invite your team': 'Zaproś swój zespół',
  'Its name is enough to start.': 'Na początek wystarczy nazwa.',
  'Who came to site today. Wages work out from it.': 'Kto przyszedł dziś na budowę. Z tego liczą się wypłaty.',
  'Speak it in your language; FieldOS writes it up.': 'Powiedz to w swoim języku; FieldOS to zapisze.',
  'Send the join code to your engineers on WhatsApp.': 'Wyślij kod dołączenia swoim inżynierom na WhatsApp.',
  'Send the invite': 'Wyślij zaproszenie',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'Wyślij przez WhatsApp lub SMS. Zawiera link do aplikacji i kroki.',
  'Join {company} on FieldOS, our site app.': 'Dołącz do {company} w FieldOS, naszej aplikacji budowlanej.',
  '1. Install it: {link}': '1. Zainstaluj: {link}',
  '2. Sign in with Google.': '2. Zaloguj się przez Google.',
  '3. Tap "Join with a code" and enter {code}': '3. Dotknij "Dołącz kodem" i wpisz {code}',
  'our company': 'naszej firmy',
  'Your free trial ends today': 'Twój darmowy okres próbny kończy się dziś',
  'Free trial: 1 day left': 'Okres próbny: został 1 dzień',
  'Free trial: {n} days left': 'Okres próbny: dni do końca: {n}',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'Potem plan zacznie się sam. Aby go zatrzymać, anuluj wcześniej w {path}.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'Okres próbny się nie odnowi. Wybierz plan, aby budowy działały dalej.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'To konto nie ma planu firmowego. Dołącz do firmy kodem od właściciela albo zaloguj się e-mailem, na który jest plan.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'Najpierw zaloguj się do firmy, potem FieldOS otworzy się sam.',
};

const Map<String, String> onboardingRo = {
  'Quickest, and no password to remember. Your team joins the same way.':
      'Cel mai rapid, fără parolă de ținut minte. Echipa ta se alătură la fel.',
  'Use a username and password instead': 'Folosește un nume de utilizator și o parolă',
  'Get your first site running': 'Pornește primul tău șantier',
  'Your site is running on FieldOS': 'Șantierul tău merge pe FieldOS',
  'Every step done. Your evening report will be ready on time.':
      'Toți pașii sunt gata. Raportul de seară va fi gata la timp.',
  '{done} of {total} done · about 5 minutes': '{done} din {total} gata · cam 5 minute',
  'Getting started': 'Primii pași',
  'Hide': 'Ascunde',
  'Add your first site': 'Adaugă primul șantier',
  "Mark today's attendance": 'Notează prezența de azi',
  "Send today's daily report": 'Trimite raportul zilnic de azi',
  'Invite your team': 'Invită-ți echipa',
  'Its name is enough to start.': 'Pentru început ajunge numele.',
  'Who came to site today. Wages work out from it.': 'Cine a venit azi pe șantier. Plățile se calculează din asta.',
  'Speak it in your language; FieldOS writes it up.': 'Spune-l în limba ta; FieldOS îl scrie.',
  'Send the join code to your engineers on WhatsApp.': 'Trimite codul de acces inginerilor tăi pe WhatsApp.',
  'Send the invite': 'Trimite invitația',
  'Send it on WhatsApp or SMS. It has the app link and the steps.':
      'Trimite-o pe WhatsApp sau SMS. Are linkul aplicației și pașii.',
  'Join {company} on FieldOS, our site app.': 'Alătură-te {company} pe FieldOS, aplicația noastră de șantier.',
  '1. Install it: {link}': '1. Instaleaz-o: {link}',
  '2. Sign in with Google.': '2. Conectează-te cu Google.',
  '3. Tap "Join with a code" and enter {code}': '3. Atinge "Alătură-te cu un cod" și introdu {code}',
  'our company': 'firma noastră',
  'Your free trial ends today': 'Perioada ta de probă gratuită se încheie azi',
  'Free trial: 1 day left': 'Probă gratuită: a rămas 1 zi',
  'Free trial: {n} days left': 'Probă gratuită: au rămas {n} zile',
  'Your plan starts on its own after that. To stop it, cancel in {path} before then.':
      'După aceea planul pornește singur. Ca să-l oprești, anulează din {path} înainte.',
  'Your trial will not renew. Choose a plan to keep your sites going.':
      'Perioada de probă nu se reînnoiește. Alege un plan ca șantierele să meargă mai departe.',
  'No company plan was found for this account. Join your company with the code from its owner, or sign in with the email the plan is under.':
      'Contul acesta nu are un plan de firmă. Alătură-te firmei cu codul de la proprietar sau conectează-te cu e-mailul planului.',
  'Sign in to your company first, then FieldOS opens by itself.':
      'Conectează-te mai întâi la firmă, apoi FieldOS se deschide singur.',
};
