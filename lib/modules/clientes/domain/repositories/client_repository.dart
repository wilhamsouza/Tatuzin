import '../entities/client.dart';

abstract interface class ClientRepository {
  Future<List<Client>> search({String query = ''});
  Future<int> create(ClientInput input);
  Future<void> update(int id, ClientInput input);
  Future<void> delete(int id);
}
