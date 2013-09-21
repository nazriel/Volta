// Most basic test.
module simple;

extern(C) void printf(const(char)*, ...);

int main()
{
	ubyte uB = 0xff;
	byte  sB = cast(byte)-1;

	printf("%p\n", cast(int)uB);
	printf("%p\n", (cast(int)uB == 0xff));

	return
		(cast(int)uB == 0xff) +
		(cast(uint)uB == cast(uint)0xff) +
		(cast(int)sB == 0xffff_ffff) +
		(cast(uint)sB == cast(uint)0xffff_ffff);
}
