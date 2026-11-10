/// "My attendance": a staff member checks in and out at a site with a
/// selfie and GPS. "Staff attendance": owners and project managers see who
/// is in today, approve the days marked away from a site, and the month's
/// days per person.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/attendance/attendance_camera.dart';
import 'package:fieldos_mobile/features/attendance/staff_attendance.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart' show monthKey;
import 'package:fieldos_mobile/features/payroll/payroll_screen.dart' show monthLabel;
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';

/// The sites someone can check in at, with their geofences: the demo site
/// only when it is the only one.
class CheckInSites {
  const CheckInSites(this.sites, this.fences);
  final List<Project> sites;
  final Map<String, ProjectGeofence> fences;

  String nameOf(String id) {
    for (final s in sites) {
      if (s.id == id) return s.name;
    }
    return tr('A site');
  }
}

final checkInSitesProvider = FutureProvider.autoDispose.family<CheckInSites, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final all = await ref.watch(projectsProvider(companyId).future);
  final sample = await sampleProjectId(db, companyId);
  final real = [for (final p in all) if (p.id != sample && p.status != 'completed') p];
  final sites = real.isEmpty ? all : real;
  final fences = <String, ProjectGeofence>{};
  for (final s in sites) {
    final f = await db.geofenceDao.effectiveFor(s.id);
    if (f != null) fences[s.id] = f;
  }
  return CheckInSites(sites, fences);
});

/// This phone's ids for the person: the local login and the cloud account.
Future<Set<String>> myUserIds(AppDatabase db, String userId) async {
  final cloud = await db.settingsDao.get(cloudUserIdKey);
  return {userId, if (cloud != null && cloud.isNotEmpty) cloud};
}

final myAttendanceProvider = FutureProvider.autoDispose.family<List<StaffAttendanceData>, String>((ref, userId) async {
  final db = ref.watch(appDatabaseProvider);
  final from = DateTime.now().subtract(const Duration(days: 62));
  return db.staffAttendanceDao.forUsers(await myUserIds(db, userId), fromDay: dayKey(from));
});

Widget statusChip(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  final (bg, fg) = switch (status) {
    'ok' || 'approved' => (scheme.primaryContainer, scheme.onPrimaryContainer),
    'pending' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    _ => (scheme.errorContainer, scheme.onErrorContainer),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(tr(staffAttendanceStatusLabels[status] ?? status), style: TextStyle(color: fg, fontSize: 12)),
  );
}

/// "38 m from the site", "2.4 km from the site", "No GPS fix" or "Site has no location".
String whereText(double? distanceM, {required bool hasFix, required bool siteHasLocation}) {
  if (!siteHasLocation) return tr('Site has no location set');
  if (!hasFix || distanceM == null) return tr('No GPS fix');
  return trf('{d} from the site', {'d': distanceText(distanceM)});
}

class MyAttendanceScreen extends ConsumerStatefulWidget {
  const MyAttendanceScreen({super.key, required this.companyId, required this.userId});
  final String companyId;
  final String userId;

  @override
  ConsumerState<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends ConsumerState<MyAttendanceScreen> {
  String? _siteId;
  bool _pickedByHand = false;
  LocationFix? _fix;
  DateTime? _fixAt;
  String? _gpsNote;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<LocationFix?> _locate() async {
    try {
      final f = await ref.read(locationServiceProvider).currentFix();
      if (!mounted) return f;
      setState(() {
        _fix = f;
        _fixAt = DateTime.now();
        _gpsNote = null;
      });
      // Start on the nearest site, unless they chose one.
      final sites = await ref.read(checkInSitesProvider(widget.companyId).future);
      final near = nearestSite(f.lat, f.lng, sites.fences);
      if (mounted && near != null && !_pickedByHand) {
        setState(() => _siteId = near.$1);
      }
      return f;
    } catch (e) {
      if (mounted) {
        setState(() => _gpsNote = e is LocationUnavailable ? e.message : tr('Could not get a GPS fix.'));
      }
      return null;
    }
  }

  /// A fix from the last two minutes, or a new one.
  Future<LocationFix?> _freshFix() async {
    final at = _fixAt;
    if (_fix != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 2)) return _fix;
    return _locate();
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await job();
      ref.invalidate(myAttendanceProvider(widget.userId));
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, tr('${e.message}'), error: true);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String?> _askReason(String why) async {
    final c = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Away from the site')),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(why),
          const SizedBox(height: 8),
          TextField(
            key: const Key('checkin-reason'),
            controller: c,
            autofocus: true,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Where are you, and why?')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(
              key: const Key('reason-save'),
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(tr('Send for OK'))),
        ],
      ),
    );
    return out == null || out.isEmpty ? null : out;
  }

  Future<void> _checkIn(CheckInSites sites) => _run(() async {
        final siteId = _siteId;
        if (siteId == null) throw ArgumentError('Choose the site.');
        final fix = await _freshFix();
        final fence = sites.fences[siteId];
        final geo = geoCheck(fix?.lat, fix?.lng, fence);
        if (!mounted) return;
        final photo = await ref
            .read(attendanceCameraProvider)
            .take(selfie: true, place: sites.nameOf(siteId), fix: fix);
        if (photo == null || !mounted) return;
        String? reason;
        if (geo.within != true) {
          reason = await _askReason(fence == null
              ? tr('This site has no location set, so your manager approves the day.')
              : fix == null
                  ? tr('There is no GPS fix, so your manager approves the day.')
                  : trf('You are {d} from {site}. Your manager approves the day.',
                      {'d': distanceText(geo.distanceM!), 'site': sites.nameOf(siteId)}));
          if (reason == null) return;
        }
        final row = await ref.read(appDatabaseProvider).staffAttendanceDao.checkIn(
              companyId: widget.companyId,
              projectId: siteId,
              userId: widget.userId,
              selfiePath: photo,
              fence: fence,
              lat: fix?.lat,
              lng: fix?.lng,
              accuracyM: fix?.accuracyM,
              reason: reason,
            );
        if (mounted) {
          showSnack(
              context,
              row.status == 'ok'
                  ? trf('Checked in at {site} at {time}', {'site': sites.nameOf(siteId), 'time': fmtTime(row.checkIn)})
                  : tr('Checked in. Your manager will approve the day.'));
        }
      });

  Future<void> _checkOut(StaffAttendanceData r, CheckInSites sites) => _run(() async {
        final fix = await _freshFix();
        if (!mounted) return;
        final photo = await ref
            .read(attendanceCameraProvider)
            .take(selfie: true, place: sites.nameOf(r.projectId), fix: fix);
        if (photo == null) return;
        final row = await ref.read(appDatabaseProvider).staffAttendanceDao.checkOut(r.id,
            fence: sites.fences[r.projectId], selfiePath: photo, lat: fix?.lat, lng: fix?.lng);
        if (mounted) {
          showSnack(context, trf('Checked out at {time}', {'time': fmtTime(row.checkOut!)}));
        }
      });

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(checkInSitesProvider(widget.companyId));
    final mine = ref.watch(myAttendanceProvider(widget.userId));
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(tr('My attendance'))),
      body: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (sites) {
          if (sites.sites.isEmpty) {
            return EmptyState(
                icon: Icons.location_city_outlined,
                title: tr('No sites yet'),
                message: tr('Once you are on a site\'s team you can check in there.'));
          }
          final rows = mine.value ?? const <StaffAttendanceData>[];
          final today = dayKey(now);
          final open = [for (final r in rows) if (r.day == today && r.checkOut == null) r];
          final done = [for (final r in rows) if (r.day == today && r.checkOut != null) r];
          final siteId = _siteId != null && sites.sites.any((s) => s.id == _siteId) ? _siteId : sites.sites.first.id;
          final fence = sites.fences[siteId];
          final geo = geoCheck(_fix?.lat, _fix?.lng, fence);
          final month = staffMonth(rows, monthKey(now), now: now);
          return RefreshIndicator(
            onRefresh: () async {
              await _locate();
              ref.invalidate(myAttendanceProvider(widget.userId));
            },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(fmtDay(now, now: now), style: theme.textTheme.titleMedium),
                    for (final r in done)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          trf('Checked out of {site} at {time}', {'site': sites.nameOf(r.projectId), 'time': fmtTime(r.checkOut!)}),
                          key: Key('done-${r.id}'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (open.isNotEmpty) ...[
                      for (final r in open) ...[
                        Row(children: [
                          Expanded(
                            child: Text(
                                trf('In at {site} since {time}', {'site': sites.nameOf(r.projectId), 'time': fmtTime(r.checkIn)}),
                                style: theme.textTheme.bodyLarge),
                          ),
                          statusChip(context, r.status),
                        ]),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('check-out'),
                          onPressed: _busy ? null : () => _checkOut(r, sites),
                          icon: const Icon(Icons.logout),
                          label: Text(tr('Check out with selfie')),
                        ),
                      ],
                    ] else ...[
                      DropdownButtonFormField<String>(
                        key: const Key('checkin-site'),
                        initialValue: siteId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Site')),
                        items: [
                          for (final s in sites.sites)
                            DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() {
                          _siteId = v;
                          _pickedByHand = true;
                        }),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(
                            geo.within == true
                                ? Icons.location_on
                                : geo.within == false
                                    ? Icons.wrong_location_outlined
                                    : Icons.location_searching,
                            size: 18,
                            color: geo.within == true ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _gpsNote ??
                                (_fix == null && fence != null
                                    ? tr('Getting your location…')
                                    : whereText(geo.distanceM, hasFix: _fix != null, siteHasLocation: fence != null)),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const Key('check-in'),
                        onPressed: _busy
                            ? null
                            : () {
                                _siteId = siteId;
                                _checkIn(sites);
                              },
                        icon: const Icon(Icons.camera_front_outlined),
                        label: Text(tr('Check in with selfie')),
                      ),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(
                  month.waiting > 0
                      ? trf('{month}: {n} days at work, {w} waiting for OK',
                          {'month': monthLabel(month.month), 'n': month.present, 'w': month.waiting})
                      : trf('{month}: {n} days at work', {'month': monthLabel(month.month), 'n': month.present}),
                  key: const Key('my-month'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('Your check-ins show here.'), textAlign: TextAlign.center),
                ),
              for (final r in rows) _DayTile(row: r, siteName: sites.nameOf(r.projectId), now: now),
            ]),
          );
        },
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.row, required this.siteName, required this.now, this.who, this.photo, this.actions});
  final StaffAttendanceData row;
  final String siteName;
  final DateTime now;
  final String? who;
  final AttendancePhoto? photo;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final out = r.checkOut;
    final times = [
      trf('In {time}', {'time': fmtTime(r.checkIn)}),
      if (out != null) trf('out {time}', {'time': fmtTime(out)}),
      if (out != null) fmtHours(out.difference(r.checkIn)),
    ].join(' · ');
    final where = whereText(r.inDistanceM, hasFix: r.inLat != null, siteHasLocation: r.inDistanceM != null || r.inLat == null);
    final file = photo == null ? null : File(photo!.filePath);
    return Card(
      key: Key('day-${r.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (file != null && file.existsSync())
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 112),
                ),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(who == null ? '${fmtDate(r.checkIn, short: true, now: now)} · $siteName' : '$who · $siteName',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                if (who != null) Text(fmtDate(r.checkIn, short: true, now: now), style: Theme.of(context).textTheme.bodySmall),
                Text(times, style: Theme.of(context).textTheme.bodySmall),
                Text(where, style: Theme.of(context).textTheme.bodySmall),
                if (r.reason != null) Text('“${r.reason}”', style: Theme.of(context).textTheme.bodySmall),
                if (r.reviewNote != null)
                  Text(trf('Manager: {note}', {'note': r.reviewNote!}), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            statusChip(context, r.status),
          ]),
          ?actions,
        ]),
      ),
    );
  }
}

// --- Managers -------------------------------------------------------------

class CompanyAttendance {
  const CompanyAttendance(this.rows, this.photos, this.names, this.sites);
  final List<StaffAttendanceData> rows;
  final Map<String, AttendancePhoto> photos;
  final Map<String, String> names;
  final CheckInSites sites;
}

final companyAttendanceProvider =
    FutureProvider.autoDispose.family<CompanyAttendance, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final sites = await ref.watch(checkInSitesProvider(companyId).future);
  final from = DateTime.now().subtract(const Duration(days: 62));
  final rows = await db.staffAttendanceDao.forCompany(companyId, fromDay: dayKey(from));
  final photos = await db.staffAttendanceDao.photosFor([for (final r in rows) ?r.inPhotoId]);
  final names = <String, String>{};
  try {
    final roster = await ref.watch(teamRosterProvider(companyId).future);
    for (final m in roster.members) {
      names[m.userId] = memberLabel(m);
    }
  } catch (_) {}
  for (final s in await db.payrollDao.staffFor(companyId)) {
    final u = s.userId;
    if (u != null) names[u] = s.name;
  }
  return CompanyAttendance(rows, photos, names, sites);
});

class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key, required this.companyId, required this.userId});
  final String companyId;
  final String userId;

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  bool _busy = false;

  String _name(CompanyAttendance d, String userId) =>
      d.names[userId] ?? (userId == widget.userId ? tr('You') : tr('Someone on the team'));

  Future<void> _decide(StaffAttendanceData r, bool approve) async {
    if (_busy) return;
    String? note;
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Turn down this day?')),
          content: TextField(
            key: const Key('reject-note'),
            controller: c,
            maxLength: 300,
            decoration: InputDecoration(labelText: tr('Why (they will see this)')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('reject-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Turn down'))),
          ],
        ),
      );
      note = c.text;
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final me = await myUserIds(ref.read(appDatabaseProvider), widget.userId);
      if (me.contains(r.userId)) throw ArgumentError('Someone else approves your own attendance.');
      await ref.read(appDatabaseProvider).staffAttendanceDao.review(r.id, approve: approve, by: widget.userId, note: note);
      ref.invalidate(companyAttendanceProvider(widget.companyId));
      if (mounted) showSnack(context, approve ? tr('Approved') : tr('Turned down'));
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, tr('${e.message}'), error: true);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(companyAttendanceProvider(widget.companyId));
    final now = DateTime.now();
    final waitingCount = data.value?.rows.where((r) => r.status == 'pending').length ?? 0;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Staff attendance')),
          bottom: TabBar(tabs: [
            Tab(text: tr('Today')),
            Tab(child: waitingCount == 0 ? Text(tr('Waiting')) : Badge.count(count: waitingCount, child: Text(tr('Waiting')))),
            Tab(text: tr('Month')),
          ]),
        ),
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
          data: (d) {
            final today = dayKey(now);
            final todays = [for (final r in d.rows) if (r.day == today) r];
            final waiting = [for (final r in d.rows) if (r.status == 'pending') r];
            Widget tile(StaffAttendanceData r, {bool decide = false}) => _DayTile(
                  row: r,
                  siteName: d.sites.nameOf(r.projectId),
                  now: now,
                  who: _name(d, r.userId),
                  photo: d.photos[r.inPhotoId],
                  actions: !decide
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
                            OutlinedButton(
                                key: Key('reject-${r.id}'),
                                onPressed: _busy ? null : () => _decide(r, false),
                                child: Text(tr('Turn down'))),
                            FilledButton(
                                key: Key('approve-${r.id}'),
                                onPressed: _busy ? null : () => _decide(r, true),
                                child: Text(tr('Approve'))),
                          ]),
                        ),
                );
            Widget list(List<StaffAttendanceData> rows, String empty, {bool decide = false}) => rows.isEmpty
                ? EmptyState(icon: Icons.how_to_reg_outlined, title: empty, message: '', compact: true)
                : ListView(padding: const EdgeInsets.all(12), children: [for (final r in rows) tile(r, decide: decide)]);
            final month = monthKey(now);
            final people = <String, List<StaffAttendanceData>>{};
            for (final r in d.rows) {
              if (r.day.startsWith(month)) (people[r.userId] ??= []).add(r);
            }
            final names = people.keys.toList()..sort((a, b) => _name(d, a).compareTo(_name(d, b)));
            return TabBarView(children: [
              list(todays, tr('Nobody has checked in today yet.')),
              list(waiting, tr('Nothing is waiting for your OK.'), decide: true),
              people.isEmpty
                  ? EmptyState(
                      icon: Icons.calendar_month_outlined,
                      title: tr('No check-ins this month yet.'),
                      message: tr('Staff check in from My attendance on their phone, with a selfie at the site.'),
                      compact: true)
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(monthLabel(month), style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final u in names)
                        Builder(builder: (context) {
                          final m = staffMonth(people[u]!, month, now: now);
                          return Card(
                            key: Key('month-$u'),
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              title: Text(_name(d, u)),
                              subtitle: Text(m.waiting > 0
                                  ? trf('{n} days at work, {w} waiting for OK', {'n': m.present, 'w': m.waiting})
                                  : trf('{n} days at work', {'n': m.present})),
                              trailing: Text('${m.present}', style: Theme.of(context).textTheme.titleLarge),
                            ),
                          );
                        }),
                    ]),
            ]);
          },
        ),
      ),
    );
  }
}
