import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;
import 'package:uri/uri.dart' show UriBuilder;

void main() async {
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
  output.writeln('[Wiki instructions](https://github.com/flutter/flutter/wiki/triage#desktop).');

  output.writeln();
  output.writeln(
    'If you come across a bug that is unrelated to desktop app development, '
    'remove the `a: desktop label` and leave a comment explaining why. '
    'That will send it back to triage.'
  );

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