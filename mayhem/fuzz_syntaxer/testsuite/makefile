CC := gcc
CFLAGS = -O2 $(EXTRA)
all: main.o
	$(CC) $(CFLAGS) -o $@ $^
%.o: %.c
	$(CC) -c $< # comment
.PHONY: all
