FROM python:3.12-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Copy the whole (allowlisted) context so a missing asset folder can never
# fail the build, unlike one COPY per directory.
COPY . .
RUN ls -la /srv/dist 2>/dev/null | head -20 || true
ENV VORTEX_DATA=/data
ENV PORT=8000
EXPOSE 8000
CMD ["python", "main.py"]
