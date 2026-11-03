import 'package:atmos_trs_system/services/faq_chatbot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bot = FaqChatbotService.instance;

  setUp(bot.resetSession);

  test('follow-up uses the destination from the previous answer', () {
    final fee = bot.replyTo('Bless Amare entrance fee');
    expect(fee, contains('80'));

    final hours = bot.replyTo('opening hours');
    expect(hours.toLowerCase(), contains('bless amare'));
    expect(hours, contains('6:00 AM'));
  });

  test('Bisaya and Tagalog questions stay in that language', () {
    final ceb = bot.replyTo('Unsaon pag check in?');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);
    expect(ceb.toLowerCase(), isNot(contains('sign in to your tourist')));

    bot.resetSession();
    final fil = bot.replyTo('Paano mag-register?');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(fil.toLowerCase(), contains('mag'));
  });

  test('a greeting is answered without asking for a destination', () {
    final hi = bot.replyTo('Hi');
    expect(hi.toLowerCase(), contains('tala'));
    expect(hi.toLowerCase(), isNot(contains('which destination')));
  });

  test('Kumusta is Bisaya and Kumusta po is Filipino', () {
    final ceb = bot.replyTo('Kumusta');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);
    expect(ceb.toLowerCase(), contains('nalipay'));

    bot.resetSession();
    final fil = bot.replyTo('Kumusta po');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(fil.toLowerCase(), contains('masaya'));
  });

  test('greetings skip account lookup and answer locally', () {
    expect(bot.needsAccountLookup('Hi'), isFalse);
    expect(bot.needsAccountLookup('my check-ins'), isTrue);

    final watch = Stopwatch()..start();
    final reply = bot.replyTo('Hi');
    watch.stop();
    expect(reply.toLowerCase(), contains('tala'));
    expect(watch.elapsedMilliseconds, lessThan(50));
  });

  test('account answers time out instead of waiting forever', () async {
    expect(
      FaqChatbotService.accountLookupTimeout,
      const Duration(seconds: 8),
    );
  });

  test('Bisaya AMORAP fee, Oroquieta restaurants, and plaza address', () {
    final fee = bot.replyTo('Pila entrance sa AMORAP?');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);
    expect(fee.toLowerCase(), contains('amorap'));
    expect(fee.toLowerCase(), contains('official'));
    expect(fee, isNot(contains(RegExp(r'₱\d'))));
    expect(fee, isNot(contains('────')));

    bot.resetSession();
    final restaurants =
        bot.replyTo('Unsa ang mga nearby restaurant sa Oroquieta?');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);
    expect(
      restaurants,
      contains('Naa koy pipila ka restaurant nga pwede nimo tan-awon'),
    );
    expect(restaurants, contains('**1.'));
    expect(restaurants, contains('**2.'));
    expect(restaurants, isNot(contains('────')));
    expect(restaurants.toLowerCase(), isNot(contains('here are some restaurants')));

    bot.resetSession();
    final plaza = bot.replyTo('Asa dapit ang Oroquieta City Plaza?');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);
    expect(plaza.toLowerCase(), contains('oroquieta'));
    expect(plaza, contains('Naa ang'));
    expect(plaza, isNot(contains('────')));
  });

  test('Tagalog AMORAP fee, nearby food, and pasyalan list', () {
    final fee = bot.replyTo('Magkano ang entrance fee sa AMORAP?');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(fee.toLowerCase(), contains('amorap'));
    expect(fee.toLowerCase(), contains('peso'));
    expect(fee, isNot(contains('────')));

    bot.resetSession();
    final food = bot.replyTo('Saan may malapit na kainan?');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(food.toLowerCase(), contains('city'));
    expect(food.toLowerCase(), isNot(contains('which city or spot')));

    bot.resetSession();
    final spots = bot.replyTo('Ano ang mga pasyalan sa Misamis Occidental?');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(spots, contains('Narito ang mga featured pasyalan'));
    expect(spots, contains('**1.'));
    expect(spots, contains('AMORAP'));
  });

  test('English AMORAP fee, nearby restaurants, and attractions', () {
    final fee = bot.replyTo('How much is the entrance fee at AMORAP?');
    expect(bot.sessionLanguage, AtmosLanguage.en);
    expect(fee.toLowerCase(), contains('amorap'));
    expect(fee.toLowerCase(), contains('exact peso'));
    expect(fee, contains('**AMORAP**'));

    bot.resetSession();
    final food = bot.replyTo('What restaurants are nearby?');
    expect(bot.sessionLanguage, AtmosLanguage.en);
    expect(food.toLowerCase(), contains('which city'));
    expect(food, contains('Oroquieta'));

    bot.resetSession();
    final spots = bot.replyTo('What tourist attractions can I visit?');
    expect(bot.sessionLanguage, AtmosLanguage.en);
    expect(spots, contains('Here are featured spots'));
    expect(spots, contains('**1.'));
  });

  test('language switches when the tourist changes language', () {
    bot.replyTo('Unsa ang mga nearby restaurant sa Oroquieta?');
    expect(bot.sessionLanguage, AtmosLanguage.ceb);

    final english = bot.replyTo('How much is the entrance fee at AMORAP?');
    expect(bot.sessionLanguage, AtmosLanguage.en);
    expect(english.toLowerCase(), contains('exact peso'));

    final tagalog = bot.replyTo('Saan may malapit na kainan?');
    expect(bot.sessionLanguage, AtmosLanguage.fil);
    expect(
      tagalog,
      contains('Narito ang ilang restaurant na maaari mong puntahan'),
    );
  });

  test('restaurant replies are numbered sections without horizontal rules', () {
    final reply = bot.replyTo('What restaurants are near Oroquieta City?');
    expect(reply, contains('Here are some restaurants you can check out'));
    expect(reply, contains("**1. Mon's Grill**"));
    expect(reply, contains('• Address:'));
    expect(reply, isNot(contains('────')));
    expect(RegExp(r'\n\n\*\*2\.').hasMatch(reply), isTrue);
  });
}
