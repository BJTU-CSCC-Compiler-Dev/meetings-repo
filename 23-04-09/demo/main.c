int getint();
void putint(int x);

int main(){
    int x, y;
    x = getint();
    y = getint();

    int z = x + y;
    x = z * (x + y);
    y = z + x;
    int r =  -y;

    putint(r);
	return 0;
}
