import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme.dart';

/// Three-section founder statement rendered as a `TabBar`:
///   1. Letter from the Founder
///   2. My Promise
///   3. What We Believe
///
/// Each tab renders the founder's verbatim prose as a single scrollable text
/// block. No bullets, no icons, no reinterpretation of the copy — the exact
/// wording and line breaks supplied by the founder are preserved.
class FounderLetterView extends StatelessWidget {
  final VoidCallback? onDismiss;
  const FounderLetterView({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Letter from the Founder'),
              Tab(text: 'My Promise'),
              Tab(text: 'What We Believe'),
            ],
          ),
          SizedBox(
            height: 520,
            child: TabBarView(
              children: [
                _ProseTab(text: _letterText, onDismiss: onDismiss),
                const _ProseTab(text: _promiseText),
                const _ProseTab(text: _beliefsText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a verbatim prose block inside a scrollable padded area. If
/// [onDismiss] is provided, an "Enter Next Chapter" action is appended below
/// the text — this is functional UI only (the copy above is unchanged).
class _ProseTab extends StatelessWidget {
  final String text;
  final VoidCallback? onDismiss;
  const _ProseTab({required this.text, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.55);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: bodyStyle),
          if (onDismiss != null) ...[
            const SizedBox(height: AppTheme.spacingLg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onDismiss,
                child: const Text('Enter Next Chapter'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Verbatim copy — DO NOT edit, summarize, or reformat ─────────────────────
// The three strings below are the founder's exact words as supplied.
// Line breaks are preserved as authored. Any change requires founder approval.

const String _letterText = '''Welcome.
If you're reading this, you're probably one of three people.
You're someone thinking about joining Next Chapter.
You're helping build Next Chapter.
Or you're simply curious about why another dating app exists.
The truth is...
Next Chapter was never supposed to be another dating app.
It was never created to compete with the biggest names in the industry.
It wasn't created to see how many people we could keep endlessly scrolling.
It wasn't built to convince people to buy expensive subscriptions just so they could talk to someone who might never answer.
Next Chapter was created because I believe people deserve something better.
After my divorce, life changed in ways I never expected.
Then an injury changed it even more.
Like so many people, I found myself starting over at a time in life when I thought I already knew what the future looked like.
Eventually I did what millions of people do.
I downloaded dating apps.
I hoped maybe they would help me meet someone.
Instead, I found endless swiping.
Paywalls.
Bots.
Fake profiles.
Features designed to keep people coming back instead of helping them move forward.
The more I looked...
the more I began to wonder if loneliness had become part of the business model.
That thought never left me.
I couldn't stop asking myself one question.
What if someone built an app that actually wanted people to leave?
Not because they were frustrated.
Not because they gave up.
But because they found the person they were looking for.
That's why Next Chapter exists.
— Derek Louks
Founder, Next Chapter''';

const String _promiseText = '''I can't promise you'll meet your soulmate.
No honest person can.
I can't promise you'll fall in love next week.
I can't promise your first date will become your last first date.
Life doesn't work that way.
But I can promise you this.
I will never build this company around your loneliness.
I will never charge you simply because you want to send someone a message.
I will never sell your personal information.
I will never rent your data.
I will never intentionally create features designed to keep you lonely just so the company makes more money.
If Next Chapter succeeds...
I hope it's because people leave.
That probably sounds strange.
Most companies measure success by how many users stay forever.
I want to measure success by something different.
How many first dates happened because of this app?
How many friendships began here?
How many people finally found someone to travel with...
have dinner with...
watch sunsets with...
laugh with...
grow old with...
If one day two people meet here, fall in love, get married, and spend the rest of their lives sitting on their front porch drinking iced tea and lemonade while laughing at each other...
then Next Chapter has done exactly what it was created to do.
And if that happens...
I have one favor to ask.
Invite me to the wedding.
Not because I expect anything.
Not because I want attention.
Just because knowing that Next Chapter helped two people build a life together would be the greatest success this company could ever have.
— Derek Louks
Founder, Next Chapter''';

const String _beliefsText = '''At Next Chapter, we believe...
People are not subscriptions.
Loneliness is not a product.
Trust is earned.
Privacy is a right.
Kindness matters.
Real conversations matter.
Second chances matter.
Everyone deserves another chapter.
Whether you're twenty-one...
or eighty-one...
whether you're looking for your first love...
or trying to find love again...
you deserve a place where people see you as a human being instead of another monthly payment.
That's the company we're building.
That's the promise we'll keep.
Welcome to Next Chapter.
Let's help each other write the next chapter of our lives.
— Derek Louks
Founder, Next Chapter''';

/// Full-page route rendered from Settings → About Next Chapter → Letter.
class FounderLetterScreen extends StatelessWidget {
  const FounderLetterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Letter from the Founder'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/about'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const FounderLetterView(),
        ),
      ),
    );
  }
}
