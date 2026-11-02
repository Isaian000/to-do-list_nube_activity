import pytest

from app import create_app


@pytest.fixture
def client():
    # sin DATABASE_URL: memoria nueva por prueba
    return create_app().test_client()


def test_get_tasks_starts_empty(client):
    response = client.get("/tasks")

    assert response.status_code == 200
    assert response.get_json() == []


def test_post_task_creates_it_and_get_lists_it(client):
    response = client.post("/tasks", json={"title": "Aprender Terraform"})

    assert response.status_code == 201
    assert response.get_json() == {"id": 1, "title": "Aprender Terraform", "done": False}
    assert client.get("/tasks").get_json() == [
        {"id": 1, "title": "Aprender Terraform", "done": False}
    ]


@pytest.mark.parametrize("body", [{}, {"title": ""}, {"title": "   "}, {"title": 123}])
def test_post_task_without_valid_title_returns_400(client, body):
    response = client.post("/tasks", json=body)

    assert response.status_code == 400
    assert client.get("/tasks").get_json() == []


def test_version_reads_app_version_env(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v1.2.3")

    response = client.get("/version")

    assert response.status_code == 200
    assert response.get_json() == {"version": "v1.2.3"}
