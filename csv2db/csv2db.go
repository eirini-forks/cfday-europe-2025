package csv2db

import (
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/BooleanCat/go-functional/v2/it"
	sq "github.com/Masterminds/squirrel"
	"github.com/cloudevents/sdk-go/v2/event"

	_ "github.com/lib/pq"
)

func HandleEvent(ctx context.Context, e event.Event) error {
	fmt.Printf("received event with data: %s", string(e.Data()))

	dbURL, err := getDBURL()
	if err != nil {
		log.Fatalf("failed to load db url: %v", err)
	}

	bucket, path, err := getObjectCoordinates(e)
	if err != nil {
		return err
	}

	if isHidden(path) {
		fmt.Printf("Ignoring hidden file: %q", path)
		return nil
	}

	objectReader, err := storageReader(ctx, bucket, path)
	if err != nil {
		return fmt.Errorf("failed to create object reader: %w", err)
	}
	defer objectReader.Close()

	records, err := csv.NewReader(objectReader).ReadAll()
	if err != nil {
		return fmt.Errorf("failed to read from object: %w", err)
	}

	if len(records) < 2 {
		fmt.Printf("ignoring object with no data")
		return nil
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("failed to open db connection: %v", err)
	}
	defer db.Close()

	tableName := strings.ToUpper(strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)))

	err = initTable(ctx, db, tableName, records[0])
	if err != nil {
		return fmt.Errorf("failed to init table: %w", err)
	}

	err = insert(ctx, db, tableName, records[1:])
	if err != nil {
		return fmt.Errorf("failed to insert records into table %q: %w", tableName, err)
	}

	return nil
}

func isHidden(path string) bool {
	for _, s := range filepath.SplitList(path) {
		if strings.HasPrefix(s, ".") {
			return true
		}
	}

	return false
}

func getObjectCoordinates(e event.Event) (string, string, error) {
	var eventObj struct {
		Name   string `json:"name"`
		Bucket string `json:"bucket"`
	}

	if err := json.Unmarshal(e.Data(), &eventObj); err != nil {
		return "", "", fmt.Errorf("failed to unmarshal event: %w", err)
	}

	return eventObj.Bucket, eventObj.Name, nil
}

func storageReader(ctx context.Context, bucketName string, objectPath string) (io.ReadCloser, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create storage client: %w", err)
	}
	defer client.Close()

	return client.Bucket(bucketName).Object(objectPath).NewReader(ctx)
}

func initTable(ctx context.Context, db *sql.DB, tableName string, columns []string) error {
	if _, err := db.ExecContext(ctx, fmt.Sprintf("DROP TABLE IF EXISTS %s", tableName)); err != nil {
		return fmt.Errorf("failed to drop table %s: %w", tableName, err)
	}

	columnDefinitions := slices.Collect(it.Map(slices.Values(columns), func(col string) string {
		return fmt.Sprintf("%s TEXT", col)
	}))
	if _, err := db.ExecContext(ctx, fmt.Sprintf("CREATE TABLE %s (%s)", tableName, strings.Join(columnDefinitions, ","))); err != nil {
		return fmt.Errorf("failed to create table %s: %w", tableName, err)
	}

	return nil
}

func insert(ctx context.Context, db *sql.DB, tableName string, records [][]string) error {
	insertBuilder := sq.Insert(tableName).PlaceholderFormat(sq.Dollar)
	for _, cols := range records {
		insertBuilder = insertBuilder.Values(asAnys(cols)...)
	}
	_, err := insertBuilder.RunWith(db).ExecContext(ctx)
	if err != nil {
		return fmt.Errorf("failed to insert records: %w", err)
	}

	return nil
}

func asAnys(values []string) []any {
	return slices.Collect(it.Map(slices.Values(values), func(v string) any {
		return v
	}))
}

func getDBURL() (string, error) {
	dbURL, ok := os.LookupEnv("ARG0")
	if !ok {
		return "", errors.New("dbURL not set")
	}

	return dbURL, nil
}
