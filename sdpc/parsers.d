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
public:

///Consumes nothing, always return OK
auto nop(R)(in auto ref R i) if (isForwardRange!R) {
	return Result!R(i);
}

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
struct token(string t) {
	import std.algorithm.comparison;
	enum string[] expects = [t];
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R) {
		import std.range : take, drop;
		alias RT = Result!(R, string, Err!R);
		auto str = take(i, t.length);
		auto retr = i.save.drop(t.length);
		if (equal(str.save, t))
			return RT(retr, t);
		return RT(Err!R(expects, false, i.save));
	}
}

/// Match any character in accept
struct ch(alias accept) if (is(ElementType!(typeof(accept)))) {
	alias Char = ElementType!(typeof(accept));
	enum string[] expects = accept.map!"[a]".array;
	static auto opCall(R)(in auto ref R i)
	if (isForwardRange!R && is(typeof(ElementType!R.init == Char.init))) {
		alias RT = Result!(R, Unqual!(ElementType!R), Err!R);
		alias V = aliasSeqOf!accept;
		if (i.empty)
			return RT(Err!R(expects, false, i));

		auto u = i.front;
		auto retr = i.save;
		switch(u) {
			// static foreach magic
			foreach(v; V) {
			case v:
				retr.popFront;
				return RT(retr, u);
			}
			default:
				return RT(Err!R(expects, false, i));
		}
	}
}

/// Match any character except those in reject
struct not_ch(alias reject) if (is(ElementType!(typeof(reject)))) {
	alias Char = ElementType!(typeof(reject));
	enum string[] e = reject.map!"[a]".array;
	static auto opCall(R)(in auto ref R i)
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
	alias digit = pipe!(ch!_digits, wrap!((ch) => cast(int)_digits.indexOf(ch)));
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
	alias number = pipe!(many!(digit!accept), wrap!((x) => x.reduce!((a,b) => a*base+b)));
}

///
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
alias word(alias accept = alphabet) = many!(ch!accept);

/// Parse an identifier, starts with a letter or _, followed by letter, _, or digits
auto identifier(R)(in auto ref R i)
if (isForwardRange!R) {
	auto ret = ch!(alphabet~"_")(i);
	alias RT = Result!(R, ElementType!R[], Err!R);
	if (!ret.ok)
		return RT(ret.err);
	auto ret2 = word!(alphabet~"_"~digits)(ret.cont);
	ElementType!R[] str = [ret.v];
	if (ret2.ok) {
		str ~= array(ret2.v);
		return RT(ret2.cont, str);
	}
	return RT(ret.cont, str);
}

///
unittest {
	auto i = "_asd1234a";
	auto rx2 = identifier(i);
	assert(rx2.ok);
	assert(!rx2.cont.length);
	assert(rx2.v == "_asd1234a");
}

/// Parse escaped character, \n, \r, \b, \" and \\
auto parse_escape1(R)(in auto ref R i)
if (isForwardRange!R) {
	alias RT = Result!(R, dchar, Err!R);
	auto r = seq!(
		discard!(token!"\\"),
		ch!"nbr\"\\")(i);
	if (!r.ok)
		return RT(r.err);
	dchar res;
	final switch(r.v.v!1) {
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
	return RT(r.cont, array(r.v));
}

///
unittest {
	auto i = "\"asdf\\n\\b\\\"\"";
	auto r = parse_string(i);
	import std.format;
	assert(r.ok);
	assert(r.v == "asdf\n\b\"", format("%s", r.v));
}

/// Skip white spaces
alias whitespace = pipe!(choice!(token!" ", token!"\n", token!"\t"));
alias ws(alias func) = pipe!(seq!(func, skip!whitespace), wrap!"a.v!0");

template token_ws(string t) {
	auto token_ws(R)(in auto ref R i)
	if (isForwardRange!R) {
		return i.ws!(token!t);
	}
}

///
unittest {
	const(char)[] i = " \n\t    ";
	auto r = skip!whitespace(i);
	assert(r.ok);
	assert(!r.cont.length);
}
