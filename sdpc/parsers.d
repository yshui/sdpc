/**
  Simple parsers

  Here are some commonly used parsers. Also as an example for how
  to use the combinators.

  Copyright: 2017 Yuxuan Shui
*/
module sdpc.parsers;
import sdpc.combinators,
       sdpc.primitives;
import std.traits,
       std.conv,
       std.meta,
       std.functional,
       std.algorithm;
import std.range : ElementType;
import std.array : array;
import std.experimental.allocator;
import std.experimental.allocator.gc_allocator : GCAllocator;
public:

struct Err(R) {
	const(string[])[] e;
	const(bool)[] inv;
	const(R)[] err_range;
	alias RangeType = R;
	Err!R opBinary(string op)(auto ref const(Err!R) o) const if (op == "+") {
		assert(e.length > 0);
		assert(o.e.length > 0);
		return Err!R(e~o.e, inv~o.inv, err_range~o.err_range);
	}
	this(const(string[])[] e, const(bool)[] inv, const(R)[] i) {
		this.e = e;
		this.inv = inv;
		this.err_range = i;
	}
	this(const(string[]) e, bool inv, R i) {
		this.e = [e];
		this.inv = [inv];
		this.err_range = [i];
	}
	private string toString1(ulong id) const {
		import std.format;
		import std.range : take, join;
		import std.string : indexOf;
		string tmp;
		if (inv[id])
			tmp = "Expecting any character/string other than: "~e[id].join(", ");
		else
			tmp = "Expecting any of the followings: "~e[id].join(", ");
		ulong mlen = e[id].map!"a.length".maxElement;
		string got;
		if (err_range[id].empty)
			got = "<EOF>";
		else
			got = err_range[id].take(mlen).to!string;
		string pos;
		static if (is(typeof(R.init.row)) && is(typeof(R.init.col)))
			return format("%s, but got %s at %s, %s", tmp, got, err_range[id].row, err_range[id].col);
		else
			return tmp~", but got "~got;
	}
	string toString() const {
		assert(e.length > 0);
		if (e.length == 1)
			return toString1(0);
		string ret = "Encoutered following errors (only need to solve one of them): \n";
		foreach(i; 0..e.length)
			ret ~= "\t"~toString1(i)~"\n";
		return ret;
	}
}

/// Match a string, return the matched string
template token(string t) {
auto token(R)(in auto ref R i)
if (isForwardRange!R) {
	import std.algorithm.comparison;
	enum string[] expects = [t];
	alias RT = Result!(R, string, Err!R);
	static struct Token {
		bool empty;
		string front;
		Err!R err;
		R cont;

		void popFront() {
			import std.range : take, drop, popFrontExactly;
			auto str = take(cont.save, t.length);
			if (equal(str, t)) {
				front = t;
				empty = false;
				cont.popFrontExactly(t.length);
				return;
			}

			empty = true;
			err = Err!R(expects, false, cont.save);
		}

		this(R i) {
			cont = i;
			popFront;
		}
	}
	return Token(i);
}}

/// Match any character in accept
template ch(alias accept) if (is(ElementType!(typeof(accept)))) {
auto ch(R)(in auto ref R i) {
	static const(string[])[] expects = [accept.map!"[a]".array];
	static bool[] inv = [false];
	alias V = aliasSeqOf!accept;
	struct Ch {
		bool empty;
		ElementType!R front;
		Err!R err;
		R cont;

		this(R i) {
			cont = i;
			popFront;
		}

		void popFront() {
			if (cont.empty) {
				empty = true;
				err = Err!R(expects, inv, [cont]);
				return;
			}

			auto u = cont.front;
			o:switch(u) {
				// static foreach magic
				foreach(v; V) {
				case v:
					empty = false;
					front = u;
					cont.popFront;
					break o;
				}
				default:
					empty = true;
					err = Err!R(expects, inv, [cont]);
					break;
			}
		}
	}
	return Ch(i);
}}

/// Match any character except those in reject
version(legacy)
struct not_ch(alias reject) if (is(ElementType!(typeof(reject)))) {
	alias Char = ElementType!(typeof(reject));
	enum string[] e = reject.map!"[a]".array;
	static auto opCall(R, alias Allocator = GCAllocator.instance)(in auto ref R i)
	if (isForwardRange!R && is(typeof(Char.init == ElementType!R.init))) {
		alias RT = Result!(R, Unqual!(ElementType!R), Err!R);
		alias V = aliasSeqOf!reject;
		if (i.empty)
			return RT(Err!R(e, true, i));

		auto u = i.front;
		auto retr = i.save;
		switch(u) {
			// static foreach magic
			foreach(v; V) {
			case v:
				return RT(Err!R(e, true, i));
			}
			default:
				retr.popFront;
				return RT(retr, u);
		}
	}
}

/// Parse a sequences of digits, return an array of number
template digit(string _digits) {
	import std.string : indexOf;
	alias digit = pmap!(ch!_digits, ch => cast(int)_digits.indexOf(ch));
}

immutable string lower = "qwertyuiopasdfghjklzxcvbnm";
immutable string upper = "QWERTYUIOPASDFGHJKLZXCVBNM";
immutable string alphabet = lower ~ upper;
immutable string digits = "0123456789";

/**
  Parse a number
  Params:
	accept = digits allowed in the number, i-th character corresponds to digit i
	base = base
*/
template number(string accept = digits, int base = 10) if (accept.length == base) {
	import std.algorithm.iteration;
	alias number = pfold!(digit!accept, (a, b) => a*base+b, 0);
}

///
version(legacy)
unittest {
	auto i = "12354";
	auto rx = number!()(i);
	assert(rx.ok);
	assert(rx.v == 12354);

	i = "ffabc";
	auto rx1 = number!(digits~"abcdef", 16)(i);
	assert(rx1.ok);
	assert(rx1.v == 1047228);
}

/**
  Parse a sequence of characters
  Params:
	accept = an array of acceptable characters
*/
version(legacy)
alias word(alias accept = alphabet) = many!(ch!accept);

/// Parse an identifier, starts with a letter or _, followed by letter, _, or digits
version(legacy)
auto identifier(R)(in auto ref R i)
if (isForwardRange!R) {
	auto ret = ch!(alphabet~"_")(i);
	alias RT = Result!(R, ElementType!R[], Err!R);
	if (!ret.ok)
		return RT(ret.err);
	auto ret2 = word!(alphabet~"_"~digits)(ret.cont);
	ElementType!R[] str = [ret.v];
	if (ret2.ok) {
		str ~= array(ret2.v[]);
		return RT(ret2.cont, str);
	}
	return RT(ret.cont, str);
}

///
version(legacy)
unittest {
	auto i = "_asd1234a";
	auto rx2 = identifier(i);
	assert(rx2.ok);
	assert(!rx2.cont.length);
	assert(rx2.v == "_asd1234a");
}

/// Parse escaped character, \n, \r, \b, \" and \\
version(legacy)
auto parse_escape1(R)(in auto ref R i)
if (isForwardRange!R) {
	alias RT = Result!(R, dchar, Err!R);
	auto r = seq!(
		discard!(token!"\\"),
		ch!"nbr\"\\")(i);
	if (!r.ok)
		return RT(r.err);
	dchar res;
	final switch(r.v[1]) {
	case 'n':
		res = '\n';
		break;
	case 'b':
		res = '\b';
		break;
	case 'r':
		res = '\r';
		break;
	case '"':
		res = '\"';
		break;
	case '\\':
		res = '\\';
		break;
	}
	return RT(r.cont, res);
}

/// Parse a string enclosed by a pair of quotes, and containing escape sequence
version(legacy)
auto parse_string(R)(in auto ref R i)
if (isForwardRange!R) {
	alias RT = Result!(R, dchar[], Err!R);
	auto r = between!(token!"\"",
		many!(choice!(
			parse_escape1,
			not_ch!"\""
		)),
	token!"\"")(i);
	if (!r.ok)
		return RT(r.err);
	return RT(r.cont, array(r.v[]));
}

///
version(legacy)
unittest {
	auto i = "\"asdf\\n\\b\\\"\"";
	auto r = parse_string(i);
	import std.format;
	assert(r.ok);
	assert(r.v == "asdf\n\b\"", format("%s", r.v));
}

/// Skip white spaces
version(legacy)
alias whitespace = pipe!(choice!(token!" ", token!"\n", token!"\t"));
version(legacy)
alias ws(alias func) = pipe!(seq!(func, skip!whitespace), wrap!"a[0]");

version(legacy)
template token_ws(string t) {
	auto token_ws(R)(in auto ref R i)
	if (isForwardRange!R) {
		return i.ws!(token!t);
	}
}

///
version(legacy)
unittest {
	const(char)[] i = " \n\t    ";
	auto r = skip!whitespace(i);
	assert(r.ok);
	assert(!r.cont.length);
}
