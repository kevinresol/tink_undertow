package tink.io.java;

import haxe.io.Bytes;
import haxe.io.BytesData;
import io.undertow.server.HttpServerExchange;
import io.undertow.io.Receiver;
import tink.streams.Stream;

using tink.CoreApi;

class UndertowSource extends Generator<Chunk, Error> {
	
	function new(target:Reader) {
		super(target.read().map(o -> switch o {
			case Success(null): End;
			case Success(chunk): Link(chunk, new UndertowSource(target));
			case Failure(e): Fail(e);
		}));
	}
	
	public static inline function wrap(receiver:Receiver) {
		return new UndertowSource(new Reader(receiver));
	}
}

private class Reader implements Receiver_PartialBytesCallback {
	final target:Receiver;
	
	var reading = false;
	var trigger:PromiseTrigger<Null<Chunk>>;
	
	public function new(target) {
		this.target = target;
	}
	
	public function read():Promise<Null<Chunk>> {
		return if(trigger == null) {
			trigger = Promise.trigger();
			final ret = trigger.asPromise(); // store ref here because receivePartialBytes may be executed synchronously thus nullifying the trigger
			if(reading) {
				target.resume();
			} else {
				reading = true;
				target.receivePartialBytes(this);
			}
			ret;
		} else {
			new Error('Already reading');
		}
	}
	
	public function handle(exchange:HttpServerExchange, message:BytesData, last:Bool) {
		if(trigger != null) {
			target.pause();
			trigger.resolve(last ? null : Bytes.ofData(message));
			trigger = null;
		} else {
			trace('no trigger');
		}
	}
}