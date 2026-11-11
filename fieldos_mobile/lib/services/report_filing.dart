import 'dart:async';

import 'package:supabase/supabase.dart';

/// Asks the server to turn waiting bug and message reports into GitHub
/// issues now (the report-to-github edge function, issue #142). Fire and
/// forget: the report is already saved, and any later call files it too.
void nudgeReportFiling(SupabaseClient client) {
  unawaited(client.functions.invoke('report-to-github').then((_) {}, onError: (_) {}));
}
