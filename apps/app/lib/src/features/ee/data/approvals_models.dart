/// Approvals, client side (EE-184, EE-292).
///
/// Until EE-292 the model was deliberately thin because the server's answer
/// was: a summary of the target and the sentence somebody wrote when they
/// asked. ADR-0018 turned that round — the row is now the approver's
/// authority to read what they are asked to decide — so a row carries its
/// CONTEXT (who asked, when, what for) to the approver, and still only the
/// summary to anybody else ([EeApproval.context] is null for them).
///
/// [EeApprovalTarget] being nullable is not defensive coding. A target really
/// can be gone — core deleted the task, the archive swept the request — and
/// the screen has to say so rather than render an empty row.
library;

import 'changes_models.dart';
import 'new_ticket_api.dart';
import 'ticket_write_api.dart';

DateTime? _date(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toLocal();

class EeApprovalTarget {
  const EeApprovalTarget({
    required this.kind,
    required this.title,
    required this.status,
    this.number,
  });

  factory EeApprovalTarget.fromJson(Map<String, dynamic> json) =>
      EeApprovalTarget(
        kind: json['kind'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        number: json['number'] as int?,
      );

  /// `ee_ticket`, `task` or `ee_change` — what this is a decision about.
  final String kind;
  final String title;
  final String status;

  /// The request's own number (EE-167), null for anything that has none.
  final int? number;
}

/// What the approver reads before deciding (EE-292) — flat and nullable,
/// because each kind fills its own half: a request its requester, service
/// and priority; a change its type, risk and window; a task its due date.
class EeApprovalContext {
  const EeApprovalContext({
    this.openedAt,
    this.requesterName,
    this.requesterKind,
    this.serviceName,
    this.unitName,
    this.excerpt,
    this.priority,
    this.processType,
    this.changeType,
    this.risk,
    this.windowStart,
    this.windowEnd,
    this.taskDueAt,
  });

  factory EeApprovalContext.fromJson(Map<String, dynamic> json) =>
      EeApprovalContext(
        openedAt: _date(json['openedAt']),
        requesterName: json['requesterName'] as String?,
        requesterKind: json['requesterKind'] as String?,
        serviceName: json['serviceName'] as String?,
        unitName: json['unitName'] as String?,
        excerpt: json['excerpt'] as String?,
        priority: json['priority'] as String?,
        processType: json['processType'] as String?,
        changeType: json['changeType'] as String?,
        risk: json['risk'] as String?,
        windowStart: _date(json['windowStart']),
        windowEnd: _date(json['windowEnd']),
        taskDueAt: _date(json['taskDueAt']),
      );

  /// When the request (change, task) was opened — the "talep tarihi".
  final DateTime? openedAt;
  final String? requesterName;

  /// `member` · `portal` · `email` · `named` (filed on somebody's behalf) ·
  /// `system` — how the person reached the desk.
  final String? requesterKind;
  final String? serviceName;
  final String? unitName;

  /// The first ~240 characters of what they wrote, whitespace folded.
  final String? excerpt;
  final String? priority;
  final String? processType;
  final String? changeType;
  final String? risk;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final DateTime? taskDueAt;
}

/// How far the signatures on the same target have got. `expired` is
/// nobody's signature and is not in any of the four.
class EeApprovalProgress {
  const EeApprovalProgress({
    this.total = 0,
    this.approved = 0,
    this.pending = 0,
    this.rejected = 0,
  });

  factory EeApprovalProgress.fromJson(Map<String, dynamic> json) =>
      EeApprovalProgress(
        total: (json['total'] as num?)?.toInt() ?? 0,
        approved: (json['approved'] as num?)?.toInt() ?? 0,
        pending: (json['pending'] as num?)?.toInt() ?? 0,
        rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      );

  final int total;
  final int approved;
  final int pending;
  final int rejected;
}

class EeApproval {
  const EeApproval({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.status,
    required this.createdAt,
    this.approverUserId,
    this.approverRoleKey,
    this.requestReason,
    this.decisionReason,
    this.decidedBy,
    this.decidedAt,
    this.dueAt,
    this.target,
    this.addressedTo = 'me',
    this.canDecide = false,
    this.live = true,
    this.approverName,
    this.requestedBy,
    this.requestedByName,
    this.decidedByName,
    this.progress = const EeApprovalProgress(),
    this.context,
  });

  factory EeApproval.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;
    final target = json['target'] == null
        ? null
        : EeApprovalTarget.fromJson(json['target'] as Map<String, dynamic>);
    return EeApproval(
      id: json['id'] as String,
      targetType: json['targetType'] as String,
      targetId: json['targetId'] as String,
      status: status,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      approverUserId: json['approverUserId'] as String?,
      approverRoleKey: json['approverRoleKey'] as String?,
      requestReason: json['requestReason'] as String?,
      decisionReason: json['decisionReason'] as String?,
      decidedBy: json['decidedBy'] as String?,
      decidedAt: _date(json['decidedAt']),
      dueAt: _date(json['dueAt']),
      target: target,
      // A server from before EE-292 sends none of the flags below; the
      // defaults are what its one screen assumed (every pending row is
      // yours to answer, every row with a target is live).
      addressedTo: json['addressedTo'] as String? ?? 'me',
      canDecide: json['canDecide'] as bool? ?? status == 'pending',
      live: json['live'] as bool? ?? target != null,
      approverName: json['approverName'] as String?,
      requestedBy: json['requestedBy'] as String?,
      requestedByName: json['requestedByName'] as String?,
      decidedByName: json['decidedByName'] as String?,
      progress: json['progress'] == null
          ? const EeApprovalProgress()
          : EeApprovalProgress.fromJson(
              json['progress'] as Map<String, dynamic>,
            ),
      context: json['context'] == null
          ? null
          : EeApprovalContext.fromJson(json['context'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String targetType;
  final String targetId;

  /// `pending`, `approved`, `rejected` or `expired`. The fourth is its own
  /// word on purpose: nobody decided anything, and a screen that drew it as a
  /// refusal would blame somebody for a silence.
  final String status;

  /// When the approval was ASKED — not when the request was opened, which is
  /// [EeApprovalContext.openedAt].
  final DateTime createdAt;
  final String? approverUserId;
  final String? approverRoleKey;

  /// Why it was asked — the sentence the approver reads before deciding.
  final String? requestReason;

  /// Why it was answered. Required for BOTH answers by the server.
  final String? decisionReason;

  final String? decidedBy;
  final DateTime? decidedAt;

  /// When it lapses. Null is a legitimate choice, not a gap.
  final DateTime? dueAt;

  /// Null when the target is gone. See the file header.
  final EeApprovalTarget? target;

  /// Whose desk it is on, from where I stand: `me` (it names me), `role`
  /// (addressed to a role I answer for) or `other`. The screen's two tabs
  /// are the first two.
  final String addressedTo;

  /// The decision door's own answer: open, and mine to answer. The screen
  /// draws no button the door would refuse.
  final bool canDecide;

  /// Whether a decision can still change anything — the target is there
  /// and nobody abandoned it. Not live rows are not counted on the badge.
  final bool live;

  /// A person's name, or a custom role's; null for a built-in role (the
  /// app has `owner`, `admin`, `member` in both languages).
  final String? approverName;
  final String? requestedBy;
  final String? requestedByName;
  final String? decidedByName;
  final EeApprovalProgress progress;

  /// What it is about — the approver's and the answerer's only.
  final EeApprovalContext? context;

  bool get isPending => status == 'pending';

  /// Counted on the badge and offered with buttons.
  bool get actionable => isPending && live && canDecide;
}

/// The badge and the door (EE-292): whether this person has anything to do
/// with approvals at all, whether they answer for their role, and how many
/// of each are waiting that a decision can still change.
class EeApprovalsSummary {
  const EeApprovalsSummary({
    required this.authority,
    required this.answersForRole,
    required this.personal,
    required this.role,
  });

  factory EeApprovalsSummary.fromJson(Map<String, dynamic> json) =>
      EeApprovalsSummary(
        authority: json['authority'] as bool? ?? false,
        answersForRole: json['answersForRole'] as bool? ?? false,
        personal: (json['personal'] as num?)?.toInt() ?? 0,
        role: (json['role'] as num?)?.toInt() ?? 0,
      );

  /// Nothing known, nothing to draw: a plain server, a personal account.
  static const none = EeApprovalsSummary(
    authority: false,
    answersForRole: false,
    personal: 0,
    role: 0,
  );

  final bool authority;
  final bool answersForRole;

  /// Waiting on me by name — the "Bende" tab.
  final int personal;

  /// Waiting on my role, mine to answer — the "Takımda" tab.
  final int role;

  /// What the navigation's badge says.
  int get total => personal + role;
}

// ── The approver's window (EE-295, the server's EE-293) ─────────────────────

/// What this person may do here, in the door's own words: read the target
/// whole, correct it, open it where it lives.
class EeApprovalAccess {
  const EeApprovalAccess({
    this.full = false,
    this.edit = false,
    this.openTarget = false,
  });

  factory EeApprovalAccess.fromJson(Map<String, dynamic> json) =>
      EeApprovalAccess(
        full: json['full'] == true,
        edit: json['edit'] == true,
        openTarget: json['openTarget'] == true,
      );

  final bool full;
  final bool edit;
  final bool openTarget;
}

class EeApprovalRequester {
  const EeApprovalRequester({this.userId, this.name, this.email, this.kind});

  factory EeApprovalRequester.fromJson(Map<String, dynamic> json) =>
      EeApprovalRequester(
        userId: json['userId'] as String?,
        name: json['name'] as String?,
        email: json['email'] as String?,
        kind: json['kind'] as String?,
      );

  final String? userId;
  final String? name;
  final String? email;

  /// `member` · `portal` · `email` · `named` · `system`.
  final String? kind;
}

/// One reply on the request — the desk's internal notes included, marked.
class EeApprovalComment {
  const EeApprovalComment({
    required this.id,
    required this.body,
    required this.internal,
    this.authorId,
    this.authorName,
    this.createdAt,
  });

  factory EeApprovalComment.fromJson(Map<String, dynamic> json) =>
      EeApprovalComment(
        id: json['id'] as String,
        body: json['body'] as String? ?? '',
        internal: json['internal'] == true,
        authorId: json['authorId'] as String?,
        authorName: json['authorName'] as String?,
        createdAt: _date(json['createdAt']),
      );

  final String id;
  final String body;
  final bool internal;
  final String? authorId;
  final String? authorName;
  final DateTime? createdAt;
}

/// One file on the request — an internal note's included, marked.
class EeApprovalFile {
  const EeApprovalFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.sizeBytes,
    required this.internal,
    this.commentId,
  });

  factory EeApprovalFile.fromJson(Map<String, dynamic> json) => EeApprovalFile(
    id: json['id'] as String,
    name: json['name'] as String,
    mime: json['mime'] as String? ?? 'application/octet-stream',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    internal: json['internal'] == true,
    commentId: json['commentId'] as String?,
  );

  final String id;
  final String name;
  final String mime;
  final int sizeBytes;
  final bool internal;
  final String? commentId;
}

/// The request, whole — what the approver decides on (ADR-0018 D18.2).
class EeApprovalRequestView {
  const EeApprovalRequestView({
    required this.id,
    required this.ref,
    required this.subject,
    required this.status,
    required this.requester,
    this.number,
    this.body,
    this.priority,
    this.impact,
    this.urgency,
    this.processType,
    this.source,
    this.createdAt,
    this.serviceId,
    this.serviceName,
    this.fields = const [],
    this.unitName,
    this.answers = const [],
    this.answerValues = const {},
    this.comments = const [],
    this.files = const [],
  });

  factory EeApprovalRequestView.fromJson(Map<String, dynamic> json) {
    final service = json['service'] as Map<String, dynamic>?;
    final answers = ((json['answers'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return EeApprovalRequestView(
      id: json['id'] as String,
      number: json['number'] as int?,
      ref: json['ref'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      body: json['body'] as String?,
      status: json['status'] as String? ?? 'new',
      priority: json['priority'] as String?,
      impact: json['impact'] as String?,
      urgency: json['urgency'] as String?,
      processType: json['processType'] as String?,
      source: json['source'] as String?,
      createdAt: _date(json['createdAt']),
      requester: EeApprovalRequester.fromJson(
        (json['requester'] as Map<String, dynamic>?) ?? const {},
      ),
      serviceId: service?['id'] as String?,
      serviceName: service?['name'] as String?,
      fields: ((service?['fields'] as List?) ?? const [])
          .map((f) => EeFormField.fromJson(f as Map<String, dynamic>))
          .toList(growable: false),
      unitName: json['unitName'] as String?,
      answers: answers.map(EeTicketAnswer.fromJson).toList(growable: false),
      answerValues: {
        for (final answer in answers)
          if (answer['key'] case final String key)
            key: answer['value'] as String? ?? '',
      },
      comments: ((json['comments'] as List?) ?? const [])
          .map((c) => EeApprovalComment.fromJson(c as Map<String, dynamic>))
          .toList(growable: false),
      files: ((json['files'] as List?) ?? const [])
          .map((f) => EeApprovalFile.fromJson(f as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String id;
  final int? number;

  /// `#1042` — what a person says out loud.
  final String ref;
  final String subject;
  final String? body;
  final String status;
  final String? priority;
  final String? impact;
  final String? urgency;
  final String? processType;
  final String? source;
  final DateTime? createdAt;
  final EeApprovalRequester requester;
  final String? serviceId;
  final String? serviceName;

  /// The questions of the form version the request answered — what the
  /// correction draws, with the same widgets the filing screen uses.
  final List<EeFormField> fields;
  final String? unitName;
  final List<EeTicketAnswer> answers;

  /// `{key: value}` of [answers], to seed the correction.
  final Map<String, String> answerValues;
  final List<EeApprovalComment> comments;
  final List<EeApprovalFile> files;
}

class EeApprovalChangeView {
  const EeApprovalChangeView({
    required this.id,
    required this.title,
    required this.status,
    this.type,
    this.risk,
    this.windowStart,
    this.windowEnd,
    this.impact,
    this.createdByName,
    this.createdAt,
  });

  factory EeApprovalChangeView.fromJson(Map<String, dynamic> json) =>
      EeApprovalChangeView(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? '',
        type: json['type'] as String?,
        risk: json['risk'] as String?,
        windowStart: _date(json['windowStart']),
        windowEnd: _date(json['windowEnd']),
        impact: json['impact'] as String?,
        createdByName: json['createdByName'] as String?,
        createdAt: _date(json['createdAt']),
      );

  final String id;
  final String title;
  final String status;
  final String? type;
  final String? risk;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final String? impact;
  final String? createdByName;
  final DateTime? createdAt;
}

class EeApprovalTaskView {
  const EeApprovalTaskView({
    required this.id,
    required this.title,
    required this.status,
    this.priority,
    this.dueAt,
    this.description,
    this.projectName,
    this.createdByName,
    this.createdAt,
  });

  factory EeApprovalTaskView.fromJson(Map<String, dynamic> json) =>
      EeApprovalTaskView(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? '',
        priority: json['priority'] as String?,
        dueAt: _date(json['dueAt']),
        description: json['description'] as String?,
        projectName: json['projectName'] as String?,
        createdByName: json['createdByName'] as String?,
        createdAt: _date(json['createdAt']),
      );

  final String id;
  final String title;
  final String status;
  final String? priority;
  final DateTime? dueAt;
  final String? description;
  final String? projectName;
  final String? createdByName;
  final DateTime? createdAt;
}

/// `GET /approvals/:id` — the row, every signature on the same thing, what
/// this person may do, and (when they may read it) the thing itself.
class EeApprovalDetail {
  const EeApprovalDetail({
    required this.approval,
    required this.signatures,
    required this.access,
    this.request,
    this.change,
    this.task,
  });

  factory EeApprovalDetail.fromJson(Map<String, dynamic> json) =>
      EeApprovalDetail(
        approval: EeApproval.fromJson(json['approval'] as Map<String, dynamic>),
        signatures: ((json['signatures'] as List?) ?? const [])
            .map((s) => EeChangeApproval.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        access: EeApprovalAccess.fromJson(
          (json['access'] as Map<String, dynamic>?) ?? const {},
        ),
        request: json['request'] == null
            ? null
            : EeApprovalRequestView.fromJson(
                json['request'] as Map<String, dynamic>,
              ),
        change: json['change'] == null
            ? null
            : EeApprovalChangeView.fromJson(
                json['change'] as Map<String, dynamic>,
              ),
        task: json['task'] == null
            ? null
            : EeApprovalTaskView.fromJson(json['task'] as Map<String, dynamic>),
      );

  final EeApproval approval;

  /// Every signature asked about the same target, oldest first — the shape a
  /// change's signature card already reads.
  final List<EeChangeApproval> signatures;
  final EeApprovalAccess access;
  final EeApprovalRequestView? request;
  final EeApprovalChangeView? change;
  final EeApprovalTaskView? task;
}
