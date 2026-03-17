import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    String path = join(await getDatabasesPath(), 'geolens.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE photos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT,
            latitude REAL,
            longitude REAL,
            heading REAL,
            altitude REAL,
            timestamp TEXT,
            caption TEXT,
            address TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE photos ADD COLUMN address TEXT');
        }
      },
    );
  }

  Future<int> insertPhoto(Map<String, dynamic> photo) async {
    final db = await database;
    return await db.insert('photos', photo);
  }

  Future<List<Map<String, dynamic>>> queryAllPhotos() async {
    final db = await database;
    return await db.query('photos', orderBy: 'id DESC');
  }

  Future<int> deletePhoto(int id) async {
    final db = await database;
    return await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }
}
