module sdpc.parsers;
import sdpc.combinators,
       sdpc.primitives;
import std.traits,
       std.string,
       std.conv;

///Match a single character, return func(indexOf, character)
auto ch(alias accept, alias func)(Stream i) {
	alias ElemTy = ReturnType!func;
	alias RetTy = ParseResult!ElemTy;
	if (i.eof())
		return RetTy(State.Err, 0, ElemTy.init);
	const(char)[] n = i.advance(1);
	auto digi = accept.indexOf(n[0]);
	if (digi < 0) {
		i.rewind(1);
		return RetTy(State.Err, 0, ElemTy.init);
	}
	return RetTy(State.OK, 1, func(digi, n[0]));
}

template digit(alias digits = "0123456789") {
	private int conv(long id, char ch) { return cast(int)id; }
	alias digit = ch!(digits, conv);
}

int digit_concat(int base = 10)(int a, int b) {
	return a*base+b;
}

immutable string alphabet = "qwertyuiopasdfghjklzxcvbnm";
immutable string digits = "0123456789";

template number(alias accept = digits, int base = 10)
if (accept.length == base) {
	alias number = chain!(digit!accept, digit_concat!base, nop);
}

template letter(alias accept = alphabet){
	private char conv(long id, char ch) { return ch; }
	alias letter = ch!(accept, conv);
}

template word(alias accept = alphabet){
	private string conv(long id, char ch) {
		return to!string(ch);
	}
	private alias letter = ch!(accept, conv);
	alias word = chain!(letter, str_concat, nop);
}

auto identifier(Stream i) {
	alias RetTy = ParseResult!string;
	auto ret = letter!(alphabet~"_")(i);
	if (ret.s != State.OK)
		return RetTy(State.Err, 0, null);
	string str = to!string(ret.result);
	auto ret2 = word!(alphabet~"_"~digits)(i);
	if (ret2.s == State.OK)
		str ~= ret2;
	return RetTy(State.OK, ret.consumed+ret2.consumed, str);
}

alias skip_whitespace = skip!(choice!(token!" ", token!"\n", token!"\t"));

string str_concat(string a, string b) {
	return a ~ b;
}

unittest {
	import std.array;
	import std.stdio;
	auto i = new BufStream("12354");
	auto r = number(i);
	assert(r.s == State.OK);
	assert(r == 12354, to!string(r));

	i = new BufStream("ffabc");
	auto r3 = number!(digits~"abcdef", 16)(i);
	assert(r3.s == State.OK);
	assert(r3 == 1047228, to!string(r3));

	i = new BufStream("_asd1234a");
	auto r2 = identifier(i);
	assert(r2.s == State.OK);
	assert(i.eof());
	assert(r2 == "_asd1234a");
}
