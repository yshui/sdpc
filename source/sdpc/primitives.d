module sdpc.primitives;
import std.algorithm;
import std.stdio;
enum State {
	OK,
	Err
}
struct ParseResult(T) {
	State s;
	size_t consumed;

	static if (!is(T == void)) {
		T t;
		@property T result() {
			assert(s == State.OK);
			return t;
		}
		alias result this;
	}
	invariant {
		assert(s == State.OK || consumed == 0);
	}
}
interface Stream {
	bool starts_with(const char[] prefix);
	string advance(size_t bytes);
	void rewind(size_t bytes);
	@property bool eof();
}

class BufStream: Stream {
	private {
		immutable(char)[] buf;
		immutable(char)[] slice;
		size_t offset;
	}
	@property pure nothrow @nogc string head() {
		return slice;
	}
	override bool starts_with(const char[] prefix) {
		import std.stdio;
		if (prefix.length > slice.length)
			return false;
		return slice.startsWith(prefix);
	}
	override string advance(size_t bytes) {
		assert(bytes <= slice.length);
		auto ret = slice[0..bytes];
		slice = slice[bytes..$];
		offset += bytes;
		return ret;
	}
	override void rewind(size_t bytes) {
		assert(bytes <= offset);
		offset -= bytes;
		slice = buf[offset..$];
	}
	@property override bool eof() {
		return slice.length == 0;
	}
	this(string str) {
		buf = str;
		slice = buf[];
		offset = 0;
	}

}

/*
class Stream {
	private File f;
	char[] buf;
	bool starts_with(const ref string prefix) {
		if (buf.len < prefix.len)
			refill(prefix.len-buf.len);
		if (buf.len < prefix.len)
			return false;
		return buf.startWith(prefix);
	}
	void refill(size_t bytes) {
		size_t pos = buf.len;
		buf.len += bytes;
		auto tmp = f.rawRead(buf[pos..$]);
		if (tmp.len != bytes)
			buf.len = pos+tmp.len;
	}
	void advance(size_t bytes) {
		assert(bytes <= buf.len);
		buf = buf[bytes..$];
	}
	this(File xf) {
		f = xf;
	}
}*/
