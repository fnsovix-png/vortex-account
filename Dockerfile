FROM python:3.12-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py durable.py ./
COPY app/build/web app/build/web
COPY anime_app/build/web anime_app/build/web
COPY dist dist
ENV VORTEX_DATA=/data
ENV PORT=8000
EXPOSE 8000
CMD ["python", "main.py"]
