/// What Mitra says out loud in the guide, in each language, the way people
/// on site really talk: the Indian language with everyday English words
/// (site, tasks, cement, report) left in English.
///
/// These are spoken lines, not screen labels. They are recorded once with
/// Sarvam's voices (tool/guide_voice/make_clips.py) and shipped as clips in
/// assets/voice/, so playing them needs no internet and costs nothing.
/// Without a clip, the phone's own voice reads the same line.
///
/// Plain Dart with language codes as keys (no Flutter imports), so the
/// recording script can read it with `dart run`.
library;

/// Clip keys: 'greet' (said when the language is picked), then 'tour_0'
/// to 'tour_11', one per tour step in order.
const guideLines = <String, Map<String, String>>{
  'en': {
    'greet': "English it is. I'm Mitra, and I'll keep things simple.",
    'tour_0': "Hi! I'm Mitra, your site buddy. Let me show you one day on a real site, Mr. Reddy's G+1 house. "
        'It takes two minutes, and your own data stays untouched.',
    'tour_1': 'All your sites are in one list. You can see straight away which site is running late. '
        'Tap a site to open its tasks, labour, money and reports.',
    'tour_2': "Can't find something? Tap Ask FieldOS at the top and just say it, like "
        '"add 5,000 for cement". It asks you once before it saves.',
    'tour_3': "Start the morning with tasks. You see how far each job has got and what's slipping. "
        "The plinth beam is late, so it's already marked in red.",
    'tour_4': 'Punch workers in as they arrive, or mark the whole gang at once. '
        'Hours, half days and overtime are worked out for you.',
    'tour_5': 'Cement has arrived. Raise a purchase order, then receive what actually came. '
        'A part delivery keeps the order open, and stock updates itself.',
    'tour_6': 'Every rupee on site is here. Money in, money spent and the balance, by category. '
        'Client bills and GST invoices are made here too.',
    'tour_7': 'Cement ran short for the column casting. Raise the issue once, with photos, '
        'and it stays open until someone marks it fixed.',
    'tour_8': 'In the evening, tap Speak report and just talk, in your language or in English. '
        'FieldOS writes the report and shares a PDF on WhatsApp.',
    'tour_9': "Saturday is wages. The wage sheet adds up each worker's days, advances and what's still due. "
        'No calculator needed.',
    'tour_10': 'Owners see every site in one place: spending against budget, progress and open problems. '
        'Not a single phone call.',
    'tour_11': "That's it, you're ready! Look around the sample site, or start your first real project. "
        'You can play this tour again from the menu any time.',
  },
  'hi': {
    'greet': 'हिंदी चुनी. मैं Mitra हूँ, आपसे हिंदी और English मिलाकर बात करूँगा.',
    'tour_0': 'नमस्ते! मैं Mitra हूँ, आपका site buddy. Mr. Reddy के G+1 house पर एक दिन कैसा होता है, '
        'वो दिखाता हूँ. बस दो minute, आपका data नहीं बदलेगा.',
    'tour_1': 'यहाँ आपकी सारी sites एक ही list में हैं. कौन सी site late चल रही है, तुरंत दिख जाता है. '
        'Site पर tap करो, tasks, labour, money सब खुल जाएगा.',
    'tour_2': "कुछ ढूँढना हो तो ऊपर Ask FieldOS दबाओ और बोलो, जैसे 'cement के लिए 5,000 add करो'. "
        'Save करने से पहले आपसे एक बार पूछेगा.',
    'tour_3': 'सुबह tasks देखो. कौन सा काम कितना हुआ, क्या late हो रहा है, सब यहीं दिखता है. '
        'Plinth beam late है, इसलिए red में है.',
    'tour_4': 'Workers आएँ तो punch in करो, या पूरी gang एक साथ mark करो. '
        'Hours, half day, overtime, सब app खुद गिन लेता है.',
    'tour_5': 'Cement आ गया. Purchase order raise करो, फिर जितना असल में आया, वो receive करो. '
        'आधी delivery हो तो order open रहता है, stock अपने आप update होता है.',
    'tour_6': 'Site का हर rupee यहाँ है. आया पैसा, खर्चा और balance, category के हिसाब से. '
        'Client bills और GST invoices भी यहीं बनते हैं.',
    'tour_7': 'Column casting के लिए cement कम पड़ गया. एक बार issue raise करो, photos के साथ, '
        'जब तक कोई fixed mark न करे, वो open रहेगा.',
    'tour_8': 'शाम को Speak report दबाओ और बस बोलो, हिंदी में या English में. '
        'FieldOS report लिखता है और PDF WhatsApp पर share करता है.',
    'tour_9': 'शनिवार को wages. हर worker के days, advance और कितना देना बाकी है, wage sheet खुद जोड़ देती है. '
        'Calculator की ज़रूरत नहीं.',
    'tour_10': 'Owners को सारी sites एक जगह दिखती हैं, budget के मुकाबले खर्चा, progress और open problems. '
        'एक भी phone call नहीं.',
    'tour_11': 'बस, आप ready हो! Sample site खुद देखो, या अपना पहला project start करो. '
        'ये tour menu से कभी भी दोबारा देख सकते हो.',
  },
  'te': {
    'greet': 'తెలుగు ఎంచుకున్నారు. నేను Mitra, మీతో తెలుగు, English కలిపి మాట్లాడతా.',
    'tour_0': 'నమస్తే! నేను Mitra, మీ site buddy ని. Mr. Reddy గారి G+1 house లో ఒక రోజు ఎలా ఉంటుందో చూపిస్తా. '
        'రెండు నిమిషాలే, మీ data ఏమీ మారదు.',
    'tour_1': 'ఇక్కడ మీ sites అన్నీ ఒకే list లో ఉంటాయి. ఏ site late అవుతుందో వెంటనే తెలుస్తుంది. '
        'Site మీద tap చేస్తే tasks, labour, money అన్నీ open అవుతాయి.',
    'tour_2': "ఏది ఎక్కడ ఉందో తెలియకపోతే, పైన Ask FieldOS నొక్కి అడగండి. ఉదాహరణకు 'cement కి 5,000 add చెయ్యి' అని చెప్పండి. "
        'Save చేసే ముందు ఒకసారి అడుగుతుంది.',
    'tour_3': 'పొద్దున్నే tasks చూడండి. ఏ పని ఎంతవరకు అయ్యిందో, ఏది late అవుతుందో ఇక్కడే కనిపిస్తుంది. '
        'Plinth beam late, అందుకే red లో ఉంది.',
    'tour_4': 'Workers రాగానే punch in చేయండి, లేదా gang మొత్తాన్ని ఒకేసారి mark చేయండి. '
        'Hours, half day, overtime అన్నీ app నే లెక్క వేస్తుంది.',
    'tour_5': 'Cement వచ్చింది. Purchase order raise చేసి, నిజంగా ఎంత వచ్చిందో అంత receive చేయండి. '
        'సగం delivery అయితే order open గానే ఉంటుంది, stock దానంతట అదే update అవుతుంది.',
    'tour_6': 'Site లో ప్రతి rupee ఇక్కడే. వచ్చిన డబ్బు, ఖర్చు, balance, category వారీగా. '
        'Client bills, GST invoices కూడా ఇక్కడే చేయొచ్చు.',
    'tour_7': 'Column casting కి cement తక్కువ పడింది. ఒకసారి issue raise చేస్తే, photos తో సహా, '
        'ఎవరైనా fixed అని mark చేసే వరకు open గానే ఉంటుంది.',
    'tour_8': 'సాయంత్రం Speak report నొక్కి మామూలుగా మాట్లాడండి, తెలుగులో అయినా English లో అయినా. '
        'FieldOS report రాసి, PDF గా WhatsApp లో share చేస్తుంది.',
    'tour_9': 'శనివారం wages. ప్రతి worker days, advance, ఇంకా ఎంత ఇవ్వాలో wage sheet లెక్క వేస్తుంది. '
        'Calculator అవసరం లేదు.',
    'tour_10': 'Owners కి sites అన్నీ ఒకే చోట కనిపిస్తాయి, budget కి ఎంత ఖర్చయ్యిందో, progress, open problems. '
        'ఒక్క phone call కూడా అవసరం లేదు.',
    'tour_11': 'అంతే, మీరు ready! Sample site ని మీరే చూడండి, లేదా మీ మొదటి project start చేయండి. '
        'ఈ tour ని menu నుంచి ఎప్పుడైనా మళ్ళీ చూడొచ్చు.',
  },
  'ta': {
    'greet': 'தமிழ் தேர்ந்தெடுத்தீங்க. நான் Mitra, உங்ககிட்ட தமிழும் English-உம் கலந்து பேசுவேன்.',
    'tour_0': 'வணக்கம்! நான் Mitra, உங்க site buddy. Mr. Reddy-யோட G+1 house-ல ஒரு நாள் எப்படி இருக்கும்னு காட்டறேன். '
        'ரெண்டு நிமிஷம் தான், உங்க data எதுவும் மாறாது.',
    'tour_1': 'இங்க உங்க sites எல்லாம் ஒரே list-ல இருக்கு. எந்த site late ஆகுதுன்னு உடனே தெரியும். '
        'Site-ஐ tap பண்ணா tasks, labour, money எல்லாம் open ஆகும்.',
    'tour_2': "எது எங்க இருக்குன்னு தெரியலைன்னா, மேல Ask FieldOS அழுத்தி கேளுங்க. உதாரணமா 'cement-க்கு 5,000 add பண்ணு'ன்னு சொல்லுங்க. "
        'Save பண்றதுக்கு முன்னாடி ஒரு தடவை கேக்கும்.',
    'tour_3': 'காலையில tasks பாருங்க. எந்த வேலை எவ்வளவு முடிஞ்சிருக்கு, எது late ஆகுதுன்னு இங்க தெரியும். '
        'Plinth beam late, அதனால red-ல இருக்கு.',
    'tour_4': 'Workers வந்ததும் punch in பண்ணுங்க, இல்லன்னா gang முழுசையும் ஒரே தடவையில mark பண்ணுங்க. '
        'Hours, half day, overtime எல்லாம் app-ஏ கணக்கு போடும்.',
    'tour_5': 'Cement வந்துடுச்சு. Purchase order raise பண்ணி, உண்மையா எவ்வளவு வந்ததோ அதை receive பண்ணுங்க. '
        'பாதி delivery-னா order open-ஆவே இருக்கும், stock தானா update ஆகும்.',
    'tour_6': 'Site-ல ஒவ்வொரு rupee-யும் இங்க தான். வந்த பணம், செலவு, balance, category வாரியா. '
        'Client bills, GST invoices கூட இங்கயே போடலாம்.',
    'tour_7': 'Column casting-க்கு cement பத்தல. ஒரு தடவை issue raise பண்ணா, photos-ஓட, '
        'யாராவது fixed-னு mark பண்ற வரைக்கும் open-ஆவே இருக்கும்.',
    'tour_8': 'சாயங்காலம் Speak report அழுத்தி சாதாரணமா பேசுங்க, தமிழ்லயோ English-லயோ. '
        'FieldOS report எழுதி, PDF-ஆ WhatsApp-ல share பண்ணும்.',
    'tour_9': 'சனிக்கிழமை wages. ஒவ்வொரு worker-ஓட days, advance, இன்னும் எவ்வளவு கொடுக்கணும்னு wage sheet கணக்கு போடும். '
        'Calculator வேண்டாம்.',
    'tour_10': 'Owners-க்கு எல்லா sites-உம் ஒரே இடத்துல தெரியும், budget-க்கு எதிரா செலவு, progress, open problems. '
        'ஒரு phone call கூட தேவையில்லை.',
    'tour_11': 'அவ்வளவு தான், நீங்க ready! Sample site-ஐ நீங்களே பாருங்க, இல்லன்னா உங்க முதல் project-ஐ start பண்ணுங்க. '
        'இந்த tour-ஐ menu-ல இருந்து எப்போ வேணாலும் மறுபடி பாக்கலாம்.',
  },
  'kn': {
    'greet': 'ಕನ್ನಡ ಆಯ್ಕೆ ಮಾಡಿದ್ರಿ. ನಾನು Mitra, ನಿಮ್ಜೊತೆ ಕನ್ನಡ, English mix ಮಾಡಿ ಮಾತಾಡ್ತೀನಿ.',
    'tour_0': 'ನಮಸ್ಕಾರ! ನಾನು Mitra, ನಿಮ್ಮ site buddy. Mr. Reddy ಅವರ G+1 house ನಲ್ಲಿ ಒಂದು ದಿನ ಹೇಗಿರುತ್ತೆ ಅಂತ ತೋರಿಸ್ತೀನಿ. '
        'ಎರಡು ನಿಮಿಷ ಅಷ್ಟೇ, ನಿಮ್ಮ data ಏನೂ ಬದಲಾಗಲ್ಲ.',
    'tour_1': 'ಇಲ್ಲಿ ನಿಮ್ಮ sites ಎಲ್ಲಾ ಒಂದೇ list ನಲ್ಲಿ ಇರುತ್ತೆ. ಯಾವ site late ಆಗ್ತಿದೆ ಅಂತ ತಕ್ಷಣ ಗೊತ್ತಾಗುತ್ತೆ. '
        'Site ಮೇಲೆ tap ಮಾಡಿದ್ರೆ tasks, labour, money ಎಲ್ಲಾ open ಆಗುತ್ತೆ.',
    'tour_2': "ಯಾವುದು ಎಲ್ಲಿದೆ ಅಂತ ಗೊತ್ತಿಲ್ಲದಿದ್ರೆ, ಮೇಲೆ Ask FieldOS ಒತ್ತಿ ಕೇಳಿ. ಉದಾಹರಣೆಗೆ 'cement ಗೆ 5,000 add ಮಾಡು' ಅಂತ ಹೇಳಿ. "
        'Save ಮಾಡೋಕೆ ಮುಂಚೆ ಒಮ್ಮೆ ಕೇಳುತ್ತೆ.',
    'tour_3': 'ಬೆಳಿಗ್ಗೆ tasks ನೋಡಿ. ಯಾವ ಕೆಲಸ ಎಷ್ಟು ಆಗಿದೆ, ಯಾವುದು late ಆಗ್ತಿದೆ ಅಂತ ಇಲ್ಲೇ ಕಾಣುತ್ತೆ. '
        'Plinth beam late, ಅದಕ್ಕೆ red ನಲ್ಲಿದೆ.',
    'tour_4': 'Workers ಬಂದಾಗ punch in ಮಾಡಿ, ಇಲ್ಲಾಂದ್ರೆ gang ಎಲ್ಲಾರನ್ನೂ ಒಂದೇ ಸಲ mark ಮಾಡಿ. '
        'Hours, half day, overtime ಎಲ್ಲಾ app ಏ ಲೆಕ್ಕ ಹಾಕುತ್ತೆ.',
    'tour_5': 'Cement ಬಂತು. Purchase order raise ಮಾಡಿ, ನಿಜವಾಗಿ ಎಷ್ಟು ಬಂತೋ ಅಷ್ಟು receive ಮಾಡಿ. '
        'ಅರ್ಧ delivery ಆದ್ರೆ order open ಆಗೇ ಇರುತ್ತೆ, stock ತಾನಾಗೇ update ಆಗುತ್ತೆ.',
    'tour_6': 'Site ನ ಪ್ರತಿ rupee ಇಲ್ಲೇ. ಬಂದ ದುಡ್ಡು, ಖರ್ಚು, balance, category ಪ್ರಕಾರ. '
        'Client bills, GST invoices ಕೂಡ ಇಲ್ಲೇ ಮಾಡಬಹುದು.',
    'tour_7': 'Column casting ಗೆ cement ಕಡಿಮೆ ಆಯ್ತು. ಒಮ್ಮೆ issue raise ಮಾಡಿದ್ರೆ, photos ಜೊತೆ, '
        'ಯಾರಾದ್ರೂ fixed ಅಂತ mark ಮಾಡೋವರೆಗೂ open ಆಗೇ ಇರುತ್ತೆ.',
    'tour_8': 'ಸಂಜೆ Speak report ಒತ್ತಿ ಸುಮ್ಮನೆ ಮಾತಾಡಿ, ಕನ್ನಡದಲ್ಲೋ English ನಲ್ಲೋ. '
        'FieldOS report ಬರೆದು, PDF ಆಗಿ WhatsApp ನಲ್ಲಿ share ಮಾಡುತ್ತೆ.',
    'tour_9': 'ಶನಿವಾರ wages. ಪ್ರತಿ worker ನ days, advance, ಇನ್ನೂ ಎಷ್ಟು ಕೊಡಬೇಕು ಅಂತ wage sheet ಲೆಕ್ಕ ಹಾಕುತ್ತೆ. '
        'Calculator ಬೇಡ.',
    'tour_10': 'Owners ಗೆ ಎಲ್ಲಾ sites ಒಂದೇ ಕಡೆ ಕಾಣುತ್ತೆ, budget ಗೆ ಎದುರು ಖರ್ಚು, progress, open problems. '
        'ಒಂದು phone call ಕೂಡ ಬೇಕಾಗಲ್ಲ.',
    'tour_11': 'ಅಷ್ಟೇ, ನೀವು ready! Sample site ನ ನೀವೇ ನೋಡಿ, ಇಲ್ಲಾಂದ್ರೆ ನಿಮ್ಮ ಮೊದಲ project start ಮಾಡಿ. '
        'ಈ tour ನ menu ಇಂದ ಯಾವಾಗ ಬೇಕಾದ್ರೂ ಮತ್ತೆ ನೋಡಬಹುದು.',
  },
  'mr': {
    'greet': 'मराठी निवडली. मी Mitra, तुमच्याशी मराठी आणि English मिसळून बोलेन.',
    'tour_0': 'नमस्कार! मी Mitra, तुमचा site buddy. Mr. Reddy यांच्या G+1 house वर एक दिवस कसा असतो ते दाखवतो. '
        'फक्त दोन मिनिटं, तुमचा data बदलणार नाही.',
    'tour_1': 'इथे तुमच्या सगळ्या sites एकाच list मध्ये आहेत. कोणती site late चालली आहे ते लगेच कळतं. '
        'Site वर tap करा, tasks, labour, money सगळं open होईल.',
    'tour_2': "काही सापडत नसेल तर वर Ask FieldOS दाबा आणि बोला, जसं 'cement साठी 5,000 add कर'. "
        'Save करण्याआधी एकदा विचारेल.',
    'tour_3': 'सकाळी tasks बघा. कोणतं काम किती झालं, काय late होतंय, सगळं इथे दिसतं. '
        'Plinth beam late आहे, म्हणून red मध्ये आहे.',
    'tour_4': 'Workers आले की punch in करा, किंवा पूर्ण gang एकदम mark करा. '
        'Hours, half day, overtime सगळं app स्वतः मोजतं.',
    'tour_5': 'Cement आलं. Purchase order raise करा, मग खरंच जितकं आलं तितकं receive करा. '
        'अर्धी delivery असेल तर order open राहते, stock आपोआप update होतो.',
    'tour_6': 'Site चा प्रत्येक rupee इथे. आलेले पैसे, खर्च आणि balance, category नुसार. '
        'Client bills आणि GST invoices पण इथेच बनतात.',
    'tour_7': 'Column casting साठी cement कमी पडलं. एकदा issue raise करा, photos सकट, '
        'कोणी fixed mark करेपर्यंत ते open राहील.',
    'tour_8': 'संध्याकाळी Speak report दाबा आणि फक्त बोला, मराठीत किंवा English मध्ये. '
        'FieldOS report लिहितं आणि PDF WhatsApp वर share करतं.',
    'tour_9': 'शनिवारी wages. प्रत्येक worker चे days, advance आणि किती देणं बाकी आहे, wage sheet स्वतः मोजते. '
        'Calculator नको.',
    'tour_10': 'Owners ना सगळ्या sites एका जागी दिसतात, budget च्या तुलनेत खर्च, progress आणि open problems. '
        'एकही phone call नको.',
    'tour_11': 'बस, तुम्ही ready आहात! Sample site स्वतः बघा, किंवा तुमचा पहिला project start करा. '
        'ही tour menu मधून कधीही परत बघू शकता.',
  },
};

/// Sarvam voice for each language: one calm male voice per language, so
/// Mitra sounds like the same person.
const guideVoices = <String, String>{
  'en': 'dev_en_conversational',
  'hi': 'aditya_hi_conversational',
  'te': 'tarun_te_narration',
  'ta': 'vijay_ta_narration',
  'kn': 'chetan_kn_conversation',
  'mr': 'nilesh_mr_conversation',
};
