package ;

import tink.http.Request;
import tink.http.Response;
import tink.http.containers.UndertowContainer;
import sys.thread.Thread;

using tink.io.Source;
using tink.CoreApi;

class Main {
	static function main() {
		final container = new UndertowContainer('localhost', 8881);
		container.run((req:IncomingRequest) -> (switch req.body {
			case Plain(src):
				src.all().next(chunk -> {
					Future.irreversible(cb -> {
						Thread.runWithEventLoop(() -> {
							// haxe.Timer.delay(cb.bind((chunk:OutgoingResponse)), 2000);
							Future.delay(2000, (chunk:OutgoingResponse)).handle(cb);
						});
					});
					
				});
			case _:
				Promise.reject(new Error('Unreachable'));
		}).recover(OutgoingResponse.reportError))
			.handle(function(o) switch o {
				case Running(state):
					// haxe.Timer.delay(() -> {
					// 	trace('shutdown');
					// 	state.shutdown(false).handle(o -> trace(o));
					// }, 5000);
				case _:
			});
	}
}