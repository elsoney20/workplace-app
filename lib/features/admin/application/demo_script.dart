/// The photo / video posts of the demo, written as if by colleagues.
/// Only used by Admin panel → Demo content; Arabic on purpose (the team's
/// language). Files live in assets/demo/; a missing file skips its post.
library;

class DemoComment {
  const DemoComment(this.by, this.body, this.minutesAgo);

  final String by;
  final String body;
  final int minutesAgo;

  Map<String, Object> toJson() => {
    'by': by,
    'body': body,
    'minutes_ago': minutesAgo,
  };
}

class DemoPost {
  const DemoPost({
    required this.author,
    required this.body,
    required this.files,
    required this.minutesAgo,
    this.announcement = false,
    this.comments = const [],
  });

  final String author;
  final String body;
  final List<String> files;
  final int minutesAgo;
  final bool announcement;
  final List<DemoComment> comments;
}

// Demo colleagues (see the demo_content migrations).
const _sara = 'de300000-0000-0000-0000-000000000001'; // Marketing
const _mohamed = 'de300000-0000-0000-0000-000000000002'; // Warehouse
const _mona = 'de300000-0000-0000-0000-000000000003'; // Customer care
const _karim = 'de300000-0000-0000-0000-000000000004'; // Branch sales
const _nour = 'de300000-0000-0000-0000-000000000005'; // HR
const _omar = 'de300000-0000-0000-0000-000000000006'; // IT

/// Oldest first, so the feed ends up newest first.
const demoPosts = <DemoPost>[
  DemoPost(
    author: _mohamed,
    minutesAgo: 26 * 60,
    files: ['dualsense.jpg'],
    body:
        'شحنة دراعات DualSense الجديدة وصلت المخزن ✅ كل الفروع هتستلم '
        'نصيبها بكرة الصبح. شكراً للشباب اللي فضلوا لحد بالليل 💪 #مخزون #PS5',
    comments: [
      DemoComment(_karim, 'فرع المعادي محتاج 10 زيادة لو ينفع 🙏', 25 * 60),
      DemoComment(_mohamed, 'هشوف المتاح وأرد عليك قبل الضهر 👍', 24 * 60),
    ],
  ),
  DemoPost(
    author: _sara,
    minutesAgo: 20 * 60,
    files: ['black_friday.jpg'],
    announcement: true,
    body:
        'عروض الجمعة البيضاء تبدأ الخميس الساعة 12 بالليل في كل الفروع 🔥 '
        'الخصومات على الأجهزة والألعاب والإكسسوارات. كل الفرق تراجع الورديات '
        'في جروب العمليات. #الجمعة_البيضاء #عروض',
    comments: [
      DemoComment(
        _mona,
        'خدمة العملاء جاهزة بالردود على الأسئلة المتكررة ✅',
        19 * 60,
      ),
    ],
  ),
  DemoPost(
    author: _karim,
    minutesAgo: 6 * 60,
    files: ['ps5.jpg'],
    body:
        'جهزنا ركن "كل أجيال بلاي ستيشن" في فرع المعادي 🎮 من PS1 لحد PS5، '
        'ومعاهم الـ PSP والـ Vita. العملاء بيتصوروا معاه طول اليوم 📸 '
        '#PlayStation #فروع',
    comments: [
      DemoComment(_omar, 'الـ PS2 ده فكرني بأيام زمان 😂', 5 * 60 + 40),
      DemoComment(_sara, 'هنعمل بيه بوست على السوشيال بكرة 📸', 5 * 60),
    ],
  ),
  DemoPost(
    author: _omar,
    minutesAgo: 4 * 60,
    files: ['setup.jpg'],
    body:
        'خلّصنا تجهيز ركن تجربة الكمبيوتر الجيمنج في فرع التجمع 🔥 '
        'كارت شاشة جامد وكيبورد وماوس جيمنج. تعالوا جربوا قبل الافتتاح '
        '#فروع #تجهيزات',
    comments: [
      DemoComment(
        _nour,
        'شكله يجنن 😍 هنعمل فيه الـ team building الجاي',
        3 * 60 + 30,
      ),
    ],
  ),
  DemoPost(
    author: _sara,
    minutesAgo: 3 * 60,
    files: ['esports.jpg', 'friends.jpg'],
    body:
        'صور من بطولة FC بين الفروع اللي عملناها الجمعة 🏆 '
        'مبروك لفريق خدمة العملاء، وهاردلك لفريق IT 😅 #بطولة #كورة',
    comments: [
      DemoComment(_omar, 'المرة الجاية ليها حساب 😤', 2 * 60 + 50),
      DemoComment(_mona, 'فريقنا مالوش حل 💪🏆', 2 * 60 + 40),
    ],
  ),
  DemoPost(
    author: _nour,
    minutesAgo: 80,
    files: ['team.jpg'],
    body:
        'ورشة التدريب على السيستم الجديد امبارح كانت ممتازة 💚 شكراً لكل '
        'اللي حضر. الورشة الجاية يوم الأحد الساعة 11، سجلوا أسماءكم في '
        'الكومنتات #تدريب #فريق_G2E',
    comments: [DemoComment(_mohamed, 'المخزن كله جاي 🎉', 60)],
  ),
  DemoPost(
    author: _mona,
    minutesAgo: 50,
    files: ['headset.jpg'],
    body:
        'أكتر سؤال بيجيلنا الأسبوع ده: أنهي سماعة تنفع PS5 والكمبيوتر مع '
        'بعض؟ 🎧 جمعت لكم إجابة جاهزة تقدروا تبعتوها للعملاء، هتلاقوها '
        'في الكومنت #عملاء #سماعات',
    comments: [
      DemoComment(
        _mona,
        'أي سماعة USB أو 3.5mm هتشتغل على الاتنين. الوايرلس لازم تكون '
        'بدونجل USB عشان تشتغل على PS5 ✅',
        45,
      ),
    ],
  ),
  DemoPost(
    author: _karim,
    minutesAgo: 30,
    files: ['switch.jpg'],
    body:
        'أجهزة Nintendo Switch رجعت تاني في كل الفروع 🎉 '
        'ومعاها باقة ألعاب العيلة بخصم خاص الأسبوع ده #نينتندو',
  ),
  DemoPost(
    author: _omar,
    minutesAgo: 15,
    files: ['gameplay.mp4', 'gameplay.jpg'],
    body:
        'فيديو قصير من ركن التجربة النهارده 🎬 الناس مش عايزة تسيب الدراع 😂 '
        '#فروع',
    comments: [DemoComment(_karim, 'ده لازم يتنزل على صفحة الشركة 🔥', 10)],
  ),
  DemoPost(
    author: _sara,
    minutesAgo: 12,
    files: ['new_arrivals.mp4', 'new_arrivals.jpg'],
    body: 'فيديو الوصل حديثاً للأسبوع ده جاهز 🎬 شاركوه مع العملاء #وصل_حديثا',
  ),
  DemoPost(
    author: _sara,
    minutesAgo: 8,
    files: ['g2e_cup.jpg'],
    body:
        'كأس بطولة الفروع وصل 🏆 مين هياخده السنة دي؟ '
        'اكتبوا توقعاتكم #بطولة',
    comments: [
      DemoComment(_karim, 'المعادي طبعاً 😎', 5),
      DemoComment(_mohamed, 'المخزن هيفاجئكم 👀', 3),
    ],
  ),
];
