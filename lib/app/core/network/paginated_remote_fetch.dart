import '../errors/app_exceptions.dart';
import 'contracts/api_client_contract.dart';

typedef JsonPageFetcher =
    Future<ApiResponse<Map<String, dynamic>>> Function({
      required int page,
      required int pageSize,
    });

Future<List<T>> fetchAllPaginatedItems<T>({
  required JsonPageFetcher fetchPage,
  required T Function(Map<String, dynamic>) fromJson,
  required String invalidItemsMessage,
  int pageSize = 100,
}) async {
  final collected = <T>[];
  var page = 1;

  while (true) {
    final response = await fetchPage(page: page, pageSize: pageSize);
    final items = response.data['items'];
    if (items is! List) {
      throw NetworkRequestException(invalidItemsMessage);
    }

    collected.addAll(items.whereType<Map<String, dynamic>>().map(fromJson));

    if (!_hasNextPage(response.data, pageSize)) {
      break;
    }

    page += 1;
  }

  return collected;
}

bool _hasNextPage(Map<String, dynamic> data, int pageSize) {
  final topLevelHasNext = data['hasNext'];
  if (topLevelHasNext is bool) {
    return topLevelHasNext;
  }

  final pagination = data['pagination'];
  if (pagination is Map<String, dynamic>) {
    final nestedHasNext = pagination['hasNext'];
    if (nestedHasNext is bool) {
      return nestedHasNext;
    }

    final nestedPage = pagination['page'];
    final nestedTotal = pagination['total'];
    if (nestedPage is num && nestedTotal is num) {
      return nestedPage * pageSize < nestedTotal;
    }
  }

  final page = data['page'];
  final total = data['total'];
  if (page is num && total is num) {
    return page * pageSize < total;
  }

  return false;
}
