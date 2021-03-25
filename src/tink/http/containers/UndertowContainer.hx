package tink.http.containers;

import java.nio.ByteBuffer;
import io.undertow.io.Sender;
import java.io.IOException;
import io.undertow.io.IoCallback;
import io.undertow.util.HttpString;
import tink.io.java.UndertowSource;
import io.undertow.server.HttpServerExchange;
import io.undertow.server.HttpHandler;
import io.undertow.Undertow;
import tink.http.Container;
import tink.http.Request;
import tink.http.Header;
import tink.streams.Stream.Handled;

using tink.http.containers.UndertowContainer;
using tink.CoreApi;

class UndertowContainer implements Container {
	final host:String;
	final port:Int;

	public function new(host, port) {
		this.host = host;
		this.port = port;
	}

	public function run(handler:Handler):Future<ContainerResult> {
		return Future.irreversible(cb -> {
			final failures = Signal.trigger();
			final server = Undertow.builder()
				.addHttpListener(port, host)
				.setHandler(handler.toUndertowHandler(failures))
				.build();
			server.start();
			cb(Running({
				shutdown: hard -> {
					new Promise((resolve, reject) -> {
						if (hard)
							reject(new Error(NotImplemented, 'Hard shutdown not implemented'));
						else {
							server.stop();
							resolve(true);
						}
						null;
					});
				},
				failures: failures,
			}));
		});
	}

	public static inline function toUndertowHandler(handler, failures):HttpHandler {
		return new UndertowHandler(handler, failures);
	}
}

private class UndertowHandler implements HttpHandler {
	final handler:Handler;
	final failures:SignalTrigger<ContainerFailure>;

	public function new(handler, failures) {
		this.handler = handler;
		this.failures = failures;
	}

	static inline function getRequest(exchange:HttpServerExchange) {
		return new IncomingRequest(
			exchange.getSourceAddress().toString(),
			new IncomingRequestHeader(
				cast exchange.getRequestMethod().toString(),
				exchange.getRequestURL(),
				exchange.getProtocol().toString(),
				[for (header in exchange.getRequestHeaders())
					new HeaderField(header.getHeaderName().toString(), [for (i in 0...header.size()) header.get(i)].join(', '))
				]
			),
			Plain(UndertowSource.wrap(exchange.getRequestReceiver()))
		);
	}

	public function handleRequest(exchange:HttpServerExchange) {
		final req = getRequest(exchange);
		handler.process(req)
			.handle(res -> {
				final headers = exchange.getResponseHeaders();
				
				for(field in res.header)
					headers.add(new HttpString(field.name), field.value);
				
				final writer = new Writer(exchange.getResponseSender());
				res.body.chunked().forEach(chunk -> {
					writer.write(chunk).map(o -> switch o {
						case Success(_): Resume;
						case Failure(e): Clog(e);
					});
				}).handle(function(o) {
					exchange.endExchange();
					switch o {
						case Clogged(e, _) /* | Failed(e) */:
							failures.trigger({
								error: e,
								request: req,
								response: res,
							});
						case _: // nothing to do
					}
				});
			});
	}
}

private class Writer implements IoCallback {
	final target:Sender;
	
	var trigger:PromiseTrigger<Noise>;
	
	public function new(target) {
		this.target = target;
	}
	
	public function write(chunk:Chunk):Promise<Noise> {
		return if(trigger == null) {
			trigger = Promise.trigger();
			final ret = trigger.asPromise();
			target.send(ByteBuffer.wrap(chunk.toBytes().getData()), this);
			ret;
		} else {
			new Error('Already writing');
		}
	}
	public function onComplete(exchange:HttpServerExchange, sender:Sender) {
		trigger.resolve(Noise);
		trigger = null;
	}

	public function onException(exchange:HttpServerExchange, sender:Sender, ex:IOException) {
		trigger.reject(Error.withData(ex.getMessage(), ex));
		trigger = null;
	}
}