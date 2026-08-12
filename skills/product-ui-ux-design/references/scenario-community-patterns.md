# Scenario Community Patterns

Use this scenario lens only when the target product is a community, social, creator, feed, topic, notification, moderation, or AI-social surface. The goal is not to reproduce source workflows; the goal is to design a polished community product with complete states and reusable design consistency.

This file merges the former community source-pattern reference and external community benchmark reference. Apply these rules only when the target surface matches; they are not the default model for finance, education, operational, or generic product UI.

## Product Surface Model

Default community surfaces:

- Home/feed: content discovery, recommendation, following feed, topic feed, and refresh/loading states.
- Detail: post/thread/content detail, comment tree, related content, AI summary or assistant entry.
- Creation: text/image/video/link creation, draft, preview, publish, failure, and post-publish feedback.
- Interaction: like, collect/bookmark, comment, reply, share, follow, join, mention, vote, react, and report.
- Identity: profile, creator card, user badges, level/points, relationship state, membership state, and privacy boundaries.
- Community/topic: topic landing, pinned content, rules, moderators, join/follow state, and activity indicators.
- Notifications: interaction notifications, system notices, moderation notices, AI task progress, and digest cards.
- Trust and safety: report, block/mute, content hidden, account restricted, sensitive content, and moderation review.
- AI interaction: assistant panel, prompt shortcuts, generated suggestions, streaming/loading, retry, citation/source, user correction, and failed-generation states.

## Source-To-Community Mapping

Translate old source patterns into community equivalents:

- Workbench/dashboard cards -> home feed modules, creator task cards, notification cards, onboarding tasks, or AI assistant suggestions.
- Exam/process states -> community workflow states such as draft, publishing, under review, visible, limited, rejected, hidden, pinned, featured, or archived.
- Sidebar/process entries -> topic navigation, creator tools, moderation queues, notification categories, or AI workspace history.
- Question/answer/analysis regions -> post body, comments, AI response, annotations, quoted content, and explanation panels.
- Answer-card/card-making settings -> creation editor settings, post format controls, audience visibility, content structure, and preview settings.
- Upload/parse/manual-correction flows -> media upload, link preview extraction, AI content parsing, draft recovery, and manual edit fallback.
- Scan/progress panels -> upload progress, generation progress, review progress, sync state, or background task state.
- Score/metric configuration -> creator/community analytics, engagement breakdown, retention indicators, quality signals, or moderation metrics.

## Interaction Principles

- Make the primary loop obvious: discover content -> react/comment/follow -> create or return.
- Keep creation entry visible but not dominant over consumption.
- Every social action needs clear pre-action, active, success, undo, disabled, and error states.
- Avoid admin-heavy density in consumer views; reserve dense layouts for creator tools, moderation, settings, analytics, and AI workspaces.
- Use optimistic UI for low-risk actions like like/bookmark/follow, but show retry/failure when the backend rejects the action.
- Use explicit copy for destructive or externally visible actions such as delete, report, block, publish, and public sharing.
- Keep AI surfaces accountable: show generation/loading, retry, edit, source/citation when relevant, and user correction paths.

## Layout Defaults

Mobile:

- Prioritize bottom navigation, thumb-friendly creation entry, feed/detail transitions, and safe-area handling.
- Use cards/lists for feeds; keep metadata compact and actions reachable.
- Prefer sheets/floating panels for comments, sharing, reporting, and quick settings.
- Avoid deep nested forms in primary consumer flows.

Web:

- Use a strong center content column for feed/detail.
- Use side panels for topic navigation, creator/AI tools, trending content, notifications, or profile context.
- Keep dense tables out of consumer discovery pages; use them only in moderation, analytics, or admin-like creator tools.
- At narrower desktop widths, collapse secondary panels before compressing content text.

## State Checklist

This is the community/social scenario state extension. The canonical generic taxonomy lives in `product-surface-patterns.md`; add these community states when the target product uses feed, creator, social, topic, notification, or moderation loops:

- Empty: first visit, no followed topics, no comments, no notifications, no search result.
- Loading: initial load, pagination, refresh, media upload, AI generation, background sync.
- Partial: content exists but media failed, comment failed, AI answer incomplete, permissions partly available.
- Error: network failure, upload failed, publish failed, moderation rejection, permission denied.
- Success: published, followed, joined, commented, shared, saved, reported.
- Reversal: unlike, unfollow, leave, undo delete where supported, cancel upload, discard draft.
- Trust: blocked user, muted topic, reported content, hidden content, sensitive warning, under review.

## Visual Tone

- Consumer-facing screens should feel approachable and active, not like an internal operations console.
- Use compact structure where it helps repeated use, but preserve breathing room around feed content and creation controls.
- Empty states should invite the next useful action, not merely explain absence.
- AI entry points should be visible and useful, but should not crowd out human community interaction.

## External Benchmark Questions

Use external community benchmarks as product-design questions, not as features to copy:

- Contribution loop: what first action does this screen enable: react, reply, follow, join, save, share, remix, create, or continue with AI?
- Feed agency: can users influence recommendations through follow/topic tuning, hide, mute, report, less-like-this, more-like-this, latest/hot/following filters, or "why am I seeing this" cues without leaving the feed?
- AI co-creation: does AI output create a next action such as continue, remix, ask follow-up, compare, regenerate, cite/source, edit, publish, save, share, or report?
- Trust and safety: are report, hide, mute/block, sensitive-content handling, moderation notice, under-review, rejected/limited, appeal, and correction states visible where needed?
- Notifications: are replies/mentions, reactions, topic/community activity, system/moderation notices, AI task progress, and digest summaries separated by urgency?
- Onboarding: does first use move users to one meaningful action before asking for broad setup?

## Community Surface Playbooks

Home/feed:

- Include feed mode switch, inline quality controls, participation actions beside content, freshness state, pagination/end state, stale/offline state, and trust labels when needed.
- Avoid passive consumption-only openings, invisible ranking when trust depends on it, and too many modes before users understand the surface.

Post/thread detail:

- Include author/context/content/media hierarchy, AI/source labels where relevant, comment/reply states, continuation paths, and moderation controls near the object.
- Avoid hiding trust controls behind ambiguous overflow icons.

Creation/publishing:

- Include draft, preview, audience/visibility, topic/tag selection, AI assistance, media upload, validation, publish, and post-publish feedback.
- Preview public/private visibility before publish when audience can vary.
- Keep AI-assisted output editable and reviewable before public posting.

Onboarding/first use:

- Ask for only the minimum preferences needed to improve the first useful feed.
- Use contextual guidance inside feed/detail/creation instead of a long tutorial.

Notifications/activity:

- Separate social, system, moderation, and AI-task notifications.
- Give each notification a destination and next action.

Moderation/trust tools:

- Consumer controls need report, hide, mute, block, sensitive reveal, and reason selection.
- Moderator controls need queue, filters, assignment, decision, notes, audit trail, bulk actions, and appeals.

## External Benchmark Sources

Use these as provenance for community-specific judgment, not as feature lists to copy:

- UX Magazine, `Seven UX Best Practices of Community Design` (`https://uxmag.com/articles/seven-ux-best-practices-of-community-design`): contribution, trust, and long-term member connection.
- Bluesky design analysis, `Designing Algorithmic Transparency` (`https://blakecrosley.com/guides/design/bluesky`): visible and user-controllable feed algorithms.
- Character.AI social-feed coverage (`https://www.tomsguide.com/ai/character-ai-just-launched-an-ai-powered-social-feed-and-its-like-tiktok-meets-chatgpt`): AI-generated artifacts as remixable, continuable, shareable units.
- Higher Logic Vanilla (`https://www.higherlogic.com/vanilla-engagement-features/`) and Circle (`https://circle.so/customization/`) feature materials: onboarding, notification, reputation, moderation, access, and customization systems.
- Activity Feed Pattern (`https://uxpatterns.dev/patterns/social/activity-feed`): real-time/pagination behavior, engagement tracking, rate limits, authorization, moderation, and audit trails.
- Discord community onboarding material (`https://docs.discord.com/developers/game-development/how-to-create-a-community-for-your-game`): controlled first exposure, clear spaces, and harm prevention.
- Social.plus community-in-app guide (`https://www.social.plus/answers/guide-to-building-an-online-community-in-your-app`): feeds, posts, comments, reactions, groups, notifications, identity, permissions, moderation, and analytics as product infrastructure.
