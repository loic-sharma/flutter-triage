import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;
import 'package:uri/uri.dart' show UriBuilder;

Future graphql() async {
  String? token = Platform.environment['GITHUB_TOKEN'];
  var query = File('github_issues.graphql').readAsStringSync();

  var uri = Uri.parse('https://api.github.com/graphql');
  var headers = <String, String>{
    'Authorization': 'bearer $token',
  };

  var output = File('issues.csv').openWrite();
  output.writeln(
    'number, title, state, createdAt, updatedAt, closedAt, '
    'author, authorUrl, comments, upvotes'
  );

  String? endCursor = null;
  var stopwatch = Stopwatch()..start();

  while (true) {
    var response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(<String, dynamic>{
        'query': query,
        'variables': <String, String?> {
          'after': endCursor,
        },
      }),
    );

    var json = jsonDecode(response.body);
    var remaining = json['data']['rateLimit']['remaining'];
    var hasNextPage = json['data']['repository']['issues']['pageInfo']['hasNextPage'];
    endCursor = json['data']['repository']['issues']['pageInfo']['endCursor'];

    List<dynamic> issueEdges = json['data']['repository']['issues']['edges'];
    var issues = issueEdges
      .map((e) => GitHubIssue.fromJson(e['node'] as Map<String, dynamic>))
      .toList();

    for (var issue in issues) {
      output
        ..write(issue.number)..write(',')
        ..writeCsvString(issue.title)..write(',')
        ..write(issue.open)..write(',')
        ..write(issue.createdAt)..write(',')
        ..write(issue.updatedAt)..write(',')
        ..write(issue.closedAt)..write(',')
        ..writeCsvString(issue.author)..write(',')
        ..writeCsvString(issue.authorUrl.toString())..write(',')
        ..write(issue.comments)..write(',')
        ..write(issue.upvotes)..writeln();
    }

    print('Time: ${stopwatch.elapsed.inSeconds}s, rate limit remaining: $remaining');

    if (!hasNextPage) {
      print('Done');
      break;
    }
  }
}

extension CsvIOSink on IOSink {
  void writeCsvString(String string) {
    if (_isComplexCsvString(string)) {
      this.write('"');
      this.write(string.replaceAll('"', '\\"'));
      this.write('"');
    } else {
      this.write(string);
    }
  }

  bool _isComplexCsvString(String value) {
    if (value.startsWith(' ') || value.endsWith(' ')) {
      return true;
    }

    for (var c in const [',', '"', "\r", '\n']) {
      if (value.contains(c)) {
        return true;
      }
    }

    return false;
  }
}

// https://api.github.com/repos/flutter/flutter/issues?state=all
class GitHubIssue {
  const GitHubIssue({
    required this.number,
    required this.url,
    required this.title,
    required this.open,
    required this.createdAt,
    required this.updatedAt,
    required this.closedAt,
    required this.author,
    required this.authorUrl,
    required this.comments,
    required this.upvotes,
    required this.labels,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    return GitHubIssue(
      number: json['number'],
      url: Uri.parse(json['url']),
      title: json['title'],
      open: json['state'] == 'OPEN',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['createdAt']),
      closedAt: DateTime.parse(json['createdAt']),
      author: json['author'] == null
        ? 'ghost'
        : json['author']['login'],
      authorUrl: json['author'] == null
        ? Uri.parse('https://github.com/ghost')
        : Uri.parse(json['author']['url']),
      comments: json['comments']['totalCount'],
      upvotes: _upvotes(json),
      labels: _labels(json),
    );
  }

  static int _upvotes(Map<String, dynamic> json) {
    for (Map<String, dynamic> reaction in json['reactionGroups']) {
      if (reaction['content'] == 'THUMBS_UP') {
        return reaction['reactors']['totalCount'];
      }
    }

    throw 'Could not find upvotes';
  }

  static List<GitHubLabel> _labels(Map<String, dynamic> json) {
    List<dynamic> labelsJson = json['labels']['nodes'];
    return labelsJson
      .map((l) => GitHubLabel.fromJson(l as Map<String, dynamic>))
      .toList();
  }

  final int number;
  final Uri url;
  final String title;
  final bool open;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime closedAt;
  final String author;
  final Uri authorUrl;
  final int comments;
  final int upvotes;
  final List<GitHubLabel> labels;
}

class GitHubLabel {
  const GitHubLabel({
    required this.name,
    required this.color,
  });

  factory GitHubLabel.fromJson(Map<String, dynamic> json) {
    return GitHubLabel(
      name: json['name'],
      color: json['color'],
    );
  }

  final String name;
  final String color;
}

void main() async {
  await graphql();
  return;

  String? token = Platform.environment['GITHUB_TOKEN'];

  var queries = const [
    TriageQuery(
      title: 'Engine pull requests',
      repo: 'flutter/engine',
      query: 'is:open is:pr label:"affects: desktop" sort:updated-asc',
    ),
    TriageQuery(
      title: 'Framework pull requests',
      repo: 'flutter/flutter',
      query: 'is:open is:pr label:"a: desktop" sort:updated-asc',
    ),
    TriageQuery(
      title: 'Bugs without priorities',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" -label:P0 -label:P1 -label:P2 -label:P3 -label:P4 -label:p5 -label:p6',
    ),
    TriageQuery(
      title: 'P0 bugs',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"P0"',
    ),
    TriageQuery(
      title: 'P1 bugs',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"P1"',
    ),
    TriageQuery(
      title: 'P2 bugs',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"P2"',
    ),
    TriageQuery(
      title: 'Flakes',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"team: flakes"',
    ),
    TriageQuery(
      title: 'Regressions',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"severe: regression"',
    ),
    TriageQuery(
      title: 'Crashes',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:updated-asc label:"severe: crash"',
    ),
    TriageQuery(
      title: 'Popular issues',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:reactions-+1-desc -label:"new feature" -label:"severe: new feature"',
    ),
    TriageQuery(
      title: 'Popular features requests',
      repo: 'flutter/flutter',
      query: 'is:open is:issue label:"a: desktop" sort:reactions-+1-desc label:"new feature"',
    ),
  ];

  // Run each triage query on GitHub API.
  var results = <TriageQueryResult>[];
  for (var triageQuery in queries) {
    results.add(TriageQueryResult(
      triageQuery: triageQuery,
      response: await searchIssues(
        'repo:${triageQuery.repo} ${triageQuery.query}',
        token: token,
      ),
    ));
  }

  // Save triage query results.
  var output = File('desktop.md').openWrite();

  output.writeln('# Flutter desktop triage');

  output.writeln('Triage queries:');
  for (var result in results) {
    var fragment = result.triageQuery.title.toLowerCase().replaceAll(' ', '-');
    output.writeln(
      '* [${result.triageQuery.title}](#$fragment) - '
      '${result.response.totalCount} open'
    );
  }

  output.writeln();
  output.writeln(
    'If you come across a bug that is unrelated to desktop app development, '
    'remove the `a: desktop label` and leave a comment explaining why. '
    'That will send it back to triage.'
  );

  output.writeln();
  output.writeln('[Wiki instructions](https://github.com/flutter/flutter/wiki/triage#desktop).');

  for (var result in results) {
    output.writeln();

    writeIssues(output, result);
  }

  await output.flush();
  output.close();
}

class TriageQuery {
  const TriageQuery({
    required this.title,
    required this.repo,
    required this.query,
  });

  final String title;
  final String repo;
  final String query;
}

class TriageQueryResult {
  const TriageQueryResult({
    required this.triageQuery,
    required this.response,
  });

  final TriageQuery triageQuery;
  final GitHubIssueSearchResponse response;
}

Future<GitHubIssueSearchResponse> searchIssues(
  String query, {
    int perPage = 10,
    String? token = null,
  }) async {
  // https://docs.github.com/en/rest/search#search-issues-and-pull-requests
  var apiUri = Uri.parse('https://api.github.com/search/issues');
  var builder = UriBuilder.fromUri(apiUri)
    ..queryParameters['q'] = query
    ..queryParameters['per_page'] = perPage.toString();

  var uri = builder.build();
  var headers = <String, String>{
    'Accept': 'application/vnd.github.text-match+json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  for (var attempt = 0; attempt < 3; attempt++) {
    var response = await http.get(uri, headers: headers);

    // Handle rate limit
    if (response.statusCode == 403) {
      // TODO: Verify this is actually rate limit exhaustion.
      // TODO: Use response to minimize sleep.
      // String? used = response.headers['x-ratelimit-used'];
      // String? reset = response.headers['x-ratelimit-reset'];
      // String? remaining = response.headers['x-ratelimit-remaining'];

      print('Rate limit exceeded on attempt ${attempt + 1}, sleeping...');
      await Future.delayed(Duration(seconds: 30));
      continue;
    }

    if (response.statusCode != 200) {
      throw 'GitHub search failed: ${response.statusCode} ${response.reasonPhrase}';
    }

    var json = jsonDecode(response.body);
    return GitHubIssueSearchResponse.fromJson(json);
  }

  throw 'GitHub search failed';
}

void writeIssues(IOSink output, TriageQueryResult result) {
  var repo = result.triageQuery.repo;
  var encodedQuery = Uri.encodeQueryComponent(result.triageQuery.query);
  var queryUrl = 'https://github.com/$repo/issues?q=$encodedQuery';

  output.writeln('## ${result.triageQuery.title}');
  output.writeln();

  output.writeln('[${result.response.totalCount} open]($queryUrl).');
  output.writeln();

  if (result.response.totalCount > 0) {
    output.writeln('Name | Comments');
    output.writeln('-- | --');

    for (var item in result.response.items) {
      var createdAt = DateFormat.yMMMMd().format(item.createdAt);
      var labels = item.labels
        .map((l) => '[`$l`](https://github.com/$repo/labels/${Uri.encodeComponent(l)})')
        .join(', ');

      output.writeln(
        '[${item.title}](${item.url})'
        '<br />'
        '<sub>'
          '$labels'
          '<br />'
          '[#${item.number}](${item.url}) opened on $createdAt '
          'by [${item.user}](${item.userUrl})'
        '</sub>'

        ' | '

        '💬 [${item.comments}](${item.url})'
      );
    }

    var isPaged = result.response.totalCount > result.response.items.length;
    if (isPaged || result.response.incompleteResults) {
      output.writeln();
      output.writeln('[See more...]($queryUrl)');
    }
  }
}

class GitHubIssueSearchResponse {
  GitHubIssueSearchResponse({
    required this.totalCount,
    required this.incompleteResults,
    required this.items,
  });

  factory GitHubIssueSearchResponse.fromJson(Map<String, dynamic> json) {
    List<dynamic> jsonItems = json['items'];

    return GitHubIssueSearchResponse(
      totalCount: json['total_count'],
      incompleteResults: json['incomplete_results'],
      items: jsonItems
        .map((i) => GitHubIssueSearchItem.fromJson(i as Map<String, dynamic>))
        .toList(),
      );
  }

  final int totalCount;
  final bool incompleteResults;
  final List<GitHubIssueSearchItem> items;
}

class GitHubIssueSearchItem {
  GitHubIssueSearchItem({
    required this.number,
    required this.url,
    required this.title,
    required this.user,
    required this.userUrl,
    required this.labels,
    required this.comments,
    required this.createdAt,
    required this.updatedAt,
    required this.closedAt,
    required this.state,
  });

  factory GitHubIssueSearchItem.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> userJson = json['user'];
    List<dynamic> labelsJson = json['labels'];
    String? closedAt = json['closed_at'];

    return GitHubIssueSearchItem(
      number: json['number'],
      url: Uri.parse(json['html_url']),
      title: json['title'],
      user: userJson['login'],
      userUrl: Uri.parse(userJson['url']),
      comments: json['comments'],
      labels: labelsJson
        .map((l) => l as Map<String, dynamic>)
        .map((l) => l['name'] as String)
        .toList(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      closedAt: closedAt != null ? DateTime.parse(closedAt) : null,
      state: json['state'],
    );
  }

  final int number;
  final Uri url;
  final String title;
  final String user;
  final Uri userUrl;
  final List<String> labels;
  final int comments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final String state;
}