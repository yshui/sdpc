module primitives;
import std.algorithms;
import std.stdio;
enum State {
	OK,
	Err
};
struct ParseResult(T) {
	enum State {
		OK,
		Err,
	};
	immutable {
		State s;
		T t;
		size_t consumed;
	}

	@property T get_result() {
		assert(s == State.OK);
		return t;
	}
	alias get_result this;
}
interface Stream {
	bool starts_with(const ref string prefix);
	void advance(size_t bytes);
	void rewind(size_t bytes);
	@property bool eof();
}

class BufStream: Stream {
	private {
		const char[] buf;
		const(char)[] slice;
		size_t offset;
	}
	override starts_with(const ref string prefix) {
		if (prefix.length > slice.length)
			return false;
		return slice.startWith(prefix);
	}
	override void advance(size_t bytes) {
		assert(bytes <= slice.length);
		slice = slice[bytes..$];
		offset += bytes;
	}
	override void rewind(size_t bytes) {
		assert(bytes <= offset);
		offset -= bytes;
		slice = buf[offset..$];
	}
	@property bool eof() {
		return slice.length == 0;
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
