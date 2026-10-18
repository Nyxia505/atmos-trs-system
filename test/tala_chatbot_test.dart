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
}
