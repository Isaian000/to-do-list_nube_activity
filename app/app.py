"""api de tareas. usa DATABASE_URL si existe, si no guarda en memoria."""
import os

from flask import Flask, jsonify, request
from sqlalchemy import Boolean, Column, Integer, String, create_engine, select
from sqlalchemy.orm import declarative_base, sessionmaker

Base = declarative_base()


class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True)
    title = Column(String(255), nullable=False)
    done = Column(Boolean, nullable=False, default=False)

    def to_dict(self):
        return {"id": self.id, "title": self.title, "done": self.done}


class MemoryStore:
    def __init__(self):
        self.tasks = []

    def list(self):
        return self.tasks

    def add(self, title, done):
        task = {"id": len(self.tasks) + 1, "title": title, "done": done}
        self.tasks.append(task)
        return task


class DatabaseStore:
    def __init__(self, url):
        engine = create_engine(url, pool_pre_ping=True)
        Base.metadata.create_all(engine)
        self.Session = sessionmaker(bind=engine)

    def list(self):
        with self.Session() as session:
            tasks = session.scalars(select(Task).order_by(Task.id)).all()
            return [t.to_dict() for t in tasks]

    def add(self, title, done):
        with self.Session() as session:
            task = Task(title=title, done=done)
            session.add(task)
            session.commit()
            return task.to_dict()


def create_app(database_url=None):
    app = Flask(__name__)
    store = DatabaseStore(database_url) if database_url else MemoryStore()

    @app.get("/tasks")
    def list_tasks():
        return jsonify(store.list())

    @app.post("/tasks")
    def create_task():
        data = request.get_json(silent=True) or {}
        title = data.get("title")
        if not isinstance(title, str) or not title.strip():
            return jsonify({"error": "El campo 'title' es obligatorio"}), 400
        done = bool(data.get("done", False))
        return jsonify(store.add(title.strip(), done)), 201

    @app.get("/version")
    def version():
        return jsonify({"version": os.environ.get("APP_VERSION", "dev")})

    @app.get("/health")
    def health():
        return jsonify({"status": "ok", "storage": type(store).__name__})

    return app


app = create_app(os.environ.get("DATABASE_URL"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
