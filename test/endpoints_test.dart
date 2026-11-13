import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netutil.dart';
import 'package:lab_daemon/state/settings_common.dart';

void main() {
  final nics = [NicInfo('Ethernet', Ipv4.parse('192.168.50.1')), NicInfo('Wi-Fi', Ipv4.parse('10.10.0.184')), NicInfo('Loopback', Ipv4.parse('127.0.0.1'))];

  group('접속 주소 (connectEndpoints)', () {
    test('기본 포트면 IP만, 다른 포트면 IP:포트', () {
      expect(connectEndpoints('192.168.50.1', '69', 69, nics), ['192.168.50.1']);
      expect(connectEndpoints('192.168.50.1', '6969', 69, nics), ['192.168.50.1:6969']);
      expect(connectEndpoints('192.168.50.1', '21', 21, nics), ['192.168.50.1']);
      expect(connectEndpoints('192.168.50.1', '2121', 21, nics), ['192.168.50.1:2121']);
    });

    test('모든 NIC에 열었으면 루프백이 아닌 NIC마다 하나씩', () {
      expect(connectEndpoints('', '69', 69, nics), ['192.168.50.1', '10.10.0.184']);
      expect(connectEndpoints('', '2121', 21, nics), ['192.168.50.1:2121', '10.10.0.184:2121']);
    });

    test('NIC가 없으면 0.0.0.0, 포트가 숫자가 아니면 기본 포트로 본다', () {
      expect(connectEndpoints('', '69', 69, const []), ['0.0.0.0']);
      expect(connectEndpoints('192.168.50.1', 'abc', 69, nics), ['192.168.50.1']);
    });
  });
}
