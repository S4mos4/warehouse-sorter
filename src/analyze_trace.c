#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    ROW_CAPACITY = 64,
    LANE_COUNT = 2,
    LANE_CAPACITY = 16,
    JAM_THRESHOLD_MS = 1000
};

static const char lane_names[] = "AB";

enum event_type { ENTRY, EXIT, TICK };

struct trace_event {
    unsigned long long time_ms;
    enum event_type type;
    size_t lane_index;
};

struct package {
    unsigned long long entry_time;
    bool jam_reported;
};

struct lane_queue {
    struct package packages[LANE_CAPACITY];
    size_t head;
    size_t count;
};

/* Return 1 for a row, 0 at the end of the file, or -1 after a read error. */
static int read_row(FILE *trace, char row[ROW_CAPACITY])
{
    size_t length = 0;
    int ch;

    while ((ch = fgetc(trace)) != EOF && ch != '\n') {
        if (ch == '\0' || length == ROW_CAPACITY - 1) {
            return -1;
        }
        row[length++] = (char)ch;
    }
    if (ferror(trace)) {
        return -1;
    }
    if (ch == EOF && length == 0) {
        return 0;
    }
    if (length > 0 && row[length - 1] == '\r') {
        --length;
    }
    row[length] = '\0';
    return 1;
}

static int trace_error(const char *path, size_t row_number, const char *message)
{
    fprintf(stderr, "%s:%zu: %s\n", path, row_number, message);
    return EXIT_FAILURE;
}

/* Split one row in place. Return an error message, or NULL on success. */
static const char *parse_event(char *row, struct trace_event *event)
{
    if (row[0] < '0' || row[0] > '9') {
        return "expected a nonnegative timestamp";
    }
    char *separator;
    errno = 0;
    event->time_ms = strtoull(row, &separator, 10);
    if (errno == ERANGE || *separator != ',') {
        return "expected timestamp,event,lane";
    }
    char *type = separator + 1;
    char *lane = strchr(type, ',');
    if (lane == NULL) {
        return "expected timestamp,event,lane";
    }
    *lane++ = '\0';

    if (strcmp(type, "TICK") == 0) {
        if (*lane != '\0') {
            return "TICK requires an empty lane field";
        }
        event->type = TICK;
        return NULL;
    }
    if (strcmp(type, "ENTRY") == 0) {
        event->type = ENTRY;
    } else if (strcmp(type, "EXIT") == 0) {
        event->type = EXIT;
    } else {
        return "expected ENTRY, EXIT, or TICK";
    }
    if ((lane[0] != 'A' && lane[0] != 'B') || lane[1] != '\0') {
        return "ENTRY and EXIT require lane A or B";
    }
    event->lane_index = lane[0] == 'A' ? 0 : 1;
    return NULL;
}

static void report_jams(struct lane_queue *queue, char lane,
                        unsigned long long time_ms)
{
    for (size_t offset = 0; offset < queue->count; ++offset) {
        size_t index = (queue->head + offset) % LANE_CAPACITY;
        struct package *package = &queue->packages[index];
        unsigned long long waiting_ms = time_ms - package->entry_time;
        if (waiting_ms < JAM_THRESHOLD_MS) {
            /* All later arrivals in this FIFO have waited less time. */
            break;
        }
        if (!package->jam_reported) {
            printf("JAM at %llu ms: lane %c package waiting for %llu ms\n",
                   time_ms, lane, waiting_ms);
            package->jam_reported = true;
        }
    }
}

static const char *apply_event(struct lane_queue queues[LANE_COUNT],
                               const struct trace_event *event)
{
    struct lane_queue *queue = &queues[event->lane_index];
    if (event->type == ENTRY && queue->count == LANE_CAPACITY) {
        return "lane queue overflow on ENTRY";
    }
    if (event->type == EXIT && queue->count == 0) {
        return "EXIT without a matching ENTRY in that lane";
    }
    for (size_t index = 0; index < LANE_COUNT; ++index) {
        report_jams(&queues[index], lane_names[index], event->time_ms);
    }
    if (event->type == ENTRY) {
        size_t tail = (queue->head + queue->count) % LANE_CAPACITY;
        queue->packages[tail] = (struct package){.entry_time = event->time_ms};
        ++queue->count;
    } else if (event->type == EXIT) {
        struct package package = queue->packages[queue->head];
        if (!package.jam_reported) {
            printf("OK at %llu ms: lane %c package exited after %llu ms\n",
                   event->time_ms, lane_names[event->lane_index],
                   event->time_ms - package.entry_time);
        }
        queue->head = (queue->head + 1) % LANE_CAPACITY;
        --queue->count;
    }
    return NULL;
}

static int analyze_trace(FILE *trace, const char *path)
{
    char row[ROW_CAPACITY];
    size_t row_number = 1;
    unsigned long long previous_time = 0;
    struct lane_queue queues[LANE_COUNT] = {0};
    int row_status = read_row(trace, row);

    if (row_status != 1 || strcmp(row, "time_ms,event,lane") != 0) {
        return trace_error(path, row_number, "expected CSV header time_ms,event,lane");
    }

    while ((row_status = read_row(trace, row)) == 1) {
        ++row_number;
        struct trace_event event = {0};
        const char *error = parse_event(row, &event);
        if (error != NULL) {
            return trace_error(path, row_number, error);
        }
        if (event.time_ms < previous_time) {
            return trace_error(path, row_number, "timestamps must be chronological");
        }
        error = apply_event(queues, &event);
        if (error != NULL) {
            return trace_error(path, row_number, error);
        }
        previous_time = event.time_ms;
    }
    if (row_status < 0) {
        return trace_error(path, row_number + 1, "unreadable or malformed CSV row");
    }
    return EXIT_SUCCESS;
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "Usage: sorter-analyze PATH.csv\n");
        return EXIT_FAILURE;
    }

    FILE *trace = fopen(argv[1], "r");
    if (trace == NULL) {
        perror(argv[1]);
        return EXIT_FAILURE;
    }
    int status = analyze_trace(trace, argv[1]);
    fclose(trace);
    return status;
}
